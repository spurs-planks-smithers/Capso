import { requireRetention } from "./retention.js";
import { fail, uploadBytes, digest, response, enabled } from "./policy.js";
import { query, authorized, nowSeconds } from "./store.js";
const LEASE_SECONDS = 120;
export async function recoverUpload(env, row, file) {
  const now = nowSeconds();
  if (
    row.status !== "reserved" ||
    row.reservation_expires_at <= now ||
    file.status !== "uploading" ||
    (file.upload_lease_until ?? 0) > now
  )
    return false;
  await requireRetention(env, row);
  const object = await env.RAW.get(file.raw_key);
  if (!object || object.size !== file.bytes) return false;
  const data = new Uint8Array(await object.arrayBuffer());
  if (data.length !== file.bytes || (await digest(data)) !== file.sha256)
    return false;
  await requireRetention(env, row);
  const recovered = await query(
    env,
    "UPDATE files SET status='uploaded',upload_claim=NULL,upload_lease_until=NULL WHERE id=? AND status='uploading' AND upload_claim IS ? AND COALESCE(upload_lease_until,0)<=? AND EXISTS(SELECT 1 FROM submissions WHERE id=? AND status='reserved' AND reservation_expires_at>?) RETURNING id",
    file.id,
    file.upload_claim ?? null,
    now,
    row.id,
    now,
  ).first();
  return !!recovered;
}
export async function recoverExpiredUploads(env) {
  const files = (
    await query(
      env,
      "SELECT files.* FROM files JOIN submissions ON submissions.id=files.submission_id WHERE files.status='uploading' AND COALESCE(files.upload_lease_until,0)<=? AND submissions.status='reserved' AND submissions.reservation_expires_at>? LIMIT 50",
      nowSeconds(),
      nowSeconds(),
    ).all()
  ).results;
  for (const file of files) {
    const row = await query(
      env,
      "SELECT * FROM submissions WHERE id=?",
      file.submission_id,
    ).first();
    try {
      if (await recoverUpload(env, row, file)) continue;
    } catch {
      continue;
    }
    await query(
      env,
      "UPDATE files SET status='pending',upload_claim=NULL,upload_lease_until=NULL WHERE id=? AND status='uploading' AND upload_claim IS ? AND COALESCE(upload_lease_until,0)<=?",
      file.id,
      file.upload_claim ?? null,
      nowSeconds(),
    ).run();
  }
}
export async function upload(request, env, id, fileID) {
  if (!enabled(env, "INTAKE_ENABLED")) fail("intake_unavailable", 503);
  const origin = request.headers.get("Origin");
  if (origin && origin !== new URL(request.url).origin)
    fail("origin_denied", 403);
  const row = await authorized(env, id, request),
    file = await query(
      env,
      "SELECT * FROM files WHERE id=? AND submission_id=?",
      fileID,
      id,
    ).first();
  if (!file) fail("not_found", 404);
  if (file.status === "uploaded") {
    await request.body?.cancel();
    return response({ received: true });
  }
  if (row.status !== "reserved" || row.reservation_expires_at <= nowSeconds())
    fail("reservation_expired", 410);
  if (await recoverUpload(env, row, file)) {
    await request.body?.cancel();
    return response({ received: true });
  }
  const claim = crypto.randomUUID(),
    key = `${id}/${fileID}/${claim}`,
    now = nowSeconds();
  const lease = await query(
    env,
    "UPDATE files SET status='uploading',upload_claim=?,upload_lease_until=?,raw_key=? WHERE id=? AND (status='pending' OR (status='uploading' AND COALESCE(upload_lease_until,0)<=?)) AND EXISTS(SELECT 1 FROM submissions WHERE id=? AND status='reserved' AND reservation_expires_at>?) RETURNING id",
    claim,
    now + LEASE_SECONDS,
    key,
    fileID,
    now,
    id,
    now,
  ).first();
  if (!lease) fail("upload_in_progress", 409);
  try {
    // Every attempt uses an immutable key, so an expired worker cannot overwrite its replacement.
    await query(
      env,
      "INSERT INTO upload_attempts(id,file_id,submission_id,raw_key) VALUES(?,?,?,?)",
      claim,
      fileID,
      id,
      key,
    ).run();
    await query(
      env,
      "INSERT OR IGNORE INTO upload_attempts(id,file_id,submission_id,raw_key) VALUES(?,?,?,?)",
      `history-${await digest(file.raw_key)}`,
      fileID,
      id,
      file.raw_key,
    ).run();
    const data = await uploadBytes(request.body, file.bytes);
    if (data.length !== file.bytes || (await digest(data)) !== file.sha256)
      fail("file_mismatch", 422);
    const current = await query(
      env,
      "SELECT id FROM files WHERE id=? AND status='uploading' AND upload_claim=? AND upload_lease_until>? AND EXISTS(SELECT 1 FROM submissions WHERE id=? AND status='reserved' AND reservation_expires_at>?)",
      fileID,
      claim,
      nowSeconds(),
      id,
      nowSeconds(),
    ).first();
    if (!current) fail("reservation_expired", 410);
    await env.RAW.put(key, data, {
      httpMetadata: { contentType: "application/octet-stream" },
      customMetadata: { submission: id },
    });
    await requireRetention(env, row);
    const stored = await query(
      env,
      "UPDATE files SET status='uploaded',upload_claim=NULL,upload_lease_until=NULL WHERE id=? AND status='uploading' AND upload_claim=? AND upload_lease_until>? AND EXISTS(SELECT 1 FROM submissions WHERE id=? AND status='reserved' AND reservation_expires_at>?) RETURNING id",
      fileID,
      claim,
      nowSeconds(),
      id,
      nowSeconds(),
    ).first();
    if (!stored) {
      const adopted = await query(
        env,
        "SELECT id FROM files WHERE id=? AND status='uploaded'",
        fileID,
      ).first();
      if (!adopted) fail("upload_in_progress", 409);
    }
    return response({ received: true });
  } catch (error) {
    // Reset ownership before cleanup so a recovering worker cannot adopt a deleted object.
    const reset = await query(
      env,
      "UPDATE files SET status='pending',upload_claim=NULL,upload_lease_until=NULL WHERE id=? AND status='uploading' AND upload_claim=? RETURNING id",
      fileID,
      claim,
    ).first();
    const adopted = reset
      ? null
      : await query(
          env,
          "SELECT id FROM files WHERE id=? AND status='uploaded' AND raw_key=?",
          fileID,
          key,
        ).first();
    if (!adopted) {
      try {
        await env.RAW.delete(key);
      } catch {
        /* Retention also tracks this attempt's private key. */
      }
    }
    throw error;
  }
}
