import { upload } from "./uploads.js";
import {
  LIMITS,
  IntakeError,
  enabled,
  fail,
  validateReservation,
  uploadBytes,
  digest,
  isID,
  publicReceipt,
  response,
} from "./policy.js";
import {
  query,
  hmac,
  nowSeconds,
  admission,
  authorized,
  submission,
  listFiles,
  tokenFor,
  enqueue,
  hold,
} from "./store.js";
async function verifyTurnstile(request, env, token) {
  if (
    !env.TURNSTILE_SECRET ||
    !env.TURNSTILE_SITE_KEY ||
    typeof token !== "string" ||
    token.length > 2048
  )
    fail("verification_required", 403);
  const verification = await fetch(
    "https://challenges.cloudflare.com/turnstile/v0/siteverify",
    {
      method: "POST",
      body: new URLSearchParams({
        secret: env.TURNSTILE_SECRET,
        response: token,
        remoteip: request.headers.get("CF-Connecting-IP") || "",
      }),
      signal: AbortSignal.timeout(10000),
    },
  );
  const result = await verification.json();
  if (
    !verification.ok ||
    !result.success ||
    result.hostname !== "feedback.nextshot.dev" ||
    result.action !== "feedback"
  )
    fail("verification_failed", 403);
}
function checkOrigin(request, env) {
  const origin = request.headers.get("Origin");
  if (origin && origin !== new URL(request.url).origin)
    fail("origin_denied", 403);
}
async function reservation(request, env) {
  if (!enabled(env, "INTAKE_ENABLED")) fail("intake_unavailable", 503);
  checkOrigin(request, env);
  if (request.headers.get("Content-Type")?.split(";")[0] !== "application/json")
    fail("content_type", 415);
  const raw = await uploadBytes(request.body, LIMITS.reservationBytes);
  let input;
  try {
    input = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(raw));
  } catch {
    fail("invalid_json");
  }
  const value = validateReservation(input);
  if (value.source === "native" && !enabled(env, "NATIVE_ENABLED"))
    fail("intake_unavailable", 503);
  const ip = request.headers.get("CF-Connecting-IP");
  if (!ip) fail("ingress_required", 403);
  const identity = await hmac(env.INTAKE_SECRET, `ip:${ip}`),
    fingerprint = await digest(JSON.stringify(value));
  const previous = await query(
    env,
    "SELECT * FROM submissions WHERE identity_hash=? AND idempotency_key=?",
    identity,
    value.idempotencyKey,
  ).first();
  if (previous) {
    if (previous.fingerprint !== fingerprint) fail("idempotency_conflict", 409);
    if (
      previous.status === "reserved" &&
      previous.reservation_expires_at < nowSeconds()
    )
      fail("reservation_expired", 410);
    return reservationResponse(env, previous);
  }
  if (value.source === "web")
    await verifyTurnstile(request, env, input.turnstileToken);
  await admission(env, identity, value.files.length > 0, value.source);
  const id = crypto.randomUUID(),
    token = await tokenFor(env, id, value.idempotencyKey),
    now = nowSeconds();
  const statements = [
    query(
      env,
      "INSERT INTO submissions(id,source,category,identity_hash,idempotency_key,fingerprint,token_hash,message,contact_email,created_at,reservation_expires_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
      id,
      value.source,
      value.category,
      identity,
      value.idempotencyKey,
      fingerprint,
      await digest(token),
      value.message,
      value.contactEmail,
      now,
      now + LIMITS.reservationSeconds,
      now + LIMITS.heldDays * 86400,
    ),
  ];
  for (const [ordinal, file] of value.files.entries()) {
    const fileID = crypto.randomUUID();
    statements.push(
      query(
        env,
        "INSERT INTO files(id,submission_id,content_type,bytes,sha256,raw_key,ordinal) VALUES(?,?,?,?,?,?,?)",
        fileID,
        id,
        file.contentType,
        file.bytes,
        file.sha256,
        `${id}/${fileID}`,
        ordinal,
      ),
    );
  }
  try {
    await env.DB.batch(statements);
  } catch {
    const existing = await query(
      env,
      "SELECT * FROM submissions WHERE identity_hash=? AND idempotency_key=?",
      identity,
      value.idempotencyKey,
    ).first();
    if (existing && existing.fingerprint === fingerprint)
      return reservationResponse(env, existing);
    throw new IntakeError("storage_unavailable", 503);
  }
  return reservationResponse(env, await submission(env, id), 201);
}
async function reservationResponse(env, row, status = 200) {
  const files = await listFiles(env, row.id);
  return response(
    {
      id: row.id,
      token: await tokenFor(env, row.id, row.idempotency_key),
      expiresAt: new Date(row.reservation_expires_at * 1000).toISOString(),
      uploads: files.map((f) => ({ id: f.id })),
    },
    status,
  );
}
async function complete(request, env, id) {
  if (!enabled(env, "INTAKE_ENABLED")) fail("intake_unavailable", 503);
  checkOrigin(request, env);
  const row = await authorized(env, id, request);
  if (row.status !== "reserved") return response(publicReceipt(row), 202);
  if (row.reservation_expires_at < nowSeconds())
    fail("reservation_expired", 410);
  const files = await listFiles(env, id);
  if (files.some((f) => f.status !== "uploaded"))
    fail("uploads_incomplete", 409);
  const changed = await query(
    env,
    "UPDATE submissions SET status='received' WHERE id=? AND status='reserved' RETURNING id",
    id,
  ).first();
  if (changed) {
    try {
      await enqueue(env, id);
    } catch {
      /* The scheduled outbox retries delivery without exposing content. */
    }
  }
  return response({ id, status: "received" }, 202);
}
export async function api(request, env) {
  const path = new URL(request.url).pathname;
  try {
    const ip = request.headers.get("CF-Connecting-IP");
    if (!ip || !env.EDGE_LIMITER) fail("ingress_unavailable", 503);
    const edge = await env.EDGE_LIMITER.limit({
      key: await hmac(env.INTAKE_SECRET, `edge:${ip}`),
    });
    if (!edge.success) fail("rate_limited", 429);
    if (path === "/v1/reservations" && request.method === "POST")
      return await reservation(request, env);
    const match = path.match(
      /^\/v1\/submissions\/([^/]+)(?:\/(complete|files)(?:\/([^/]+))?)?$/,
    );
    if (!match || !isID(match[1])) return response({ error: "not_found" }, 404);
    const [, id, action, fileID] = match;
    if (action === "files" && isID(fileID) && request.method === "PUT")
      return await upload(request, env, id, fileID);
    if (action === "complete" && !fileID && request.method === "POST")
      return await complete(request, env, id);
    if (!action && request.method === "GET")
      return response(publicReceipt(await authorized(env, id, request)));
    return response({ error: "not_found" }, 404);
  } catch (error) {
    return response(
      {
        error:
          error instanceof IntakeError ? error.code : "service_unavailable",
      },
      error instanceof IntakeError ? error.status : 503,
    );
  }
}
