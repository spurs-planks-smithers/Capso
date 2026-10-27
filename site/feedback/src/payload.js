import {
  LIMITS,
  fail,
  isID,
  isHash,
  digest,
  bounded,
  email,
} from "./policy.js";
import { requireRetention } from "./retention.js";
const now = () => Math.floor(Date.now() / 1000);
export const PRIVATE_FIELDS = Object.freeze([
  "message",
  "contact_email",
  "screened_text",
  "review_text",
  "draft_json",
  "approval_json",
  "reason_codes",
]);
const defaults = {
  message: "",
  contact_email: "",
  screened_text: null,
  review_text: null,
  draft_json: null,
  approval_json: null,
  reason_codes: "[]",
};
const MAX_PAYLOAD = 400000;
const META_FIELDS = new Set([
  "status",
  "queued",
  "notified",
  "notification_claim",
  "notification_lease_until",
  "scan_claim",
  "scan_lease_until",
  "scan_metadata",
  "draft_status",
  "review_proof",
  "review_fingerprint",
  "review_policy",
  "review_expires_at",
  "expires_at",
  "fingerprint",
]);
export const payloadKey = (id, generation) =>
  `payloads/${id}/${generation}.json`;
export const metadata = (env, id) =>
  env.DB.prepare("SELECT * FROM submissions WHERE id=?").bind(id).first();
function content(value) {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.keys(value).length !== PRIVATE_FIELDS.length ||
    Object.keys(value).some((key) => !PRIVATE_FIELDS.includes(key))
  )
    fail("payload_invalid", 503);
  for (const field of PRIVATE_FIELDS) {
    const item = value[field];
    if (
      item === null &&
      ["screened_text", "review_text", "draft_json", "approval_json"].includes(
        field,
      )
    )
      continue;
    bounded(item, field === "contact_email" ? 254 : LIMITS.textBytes);
  }
  if (value.contact_email && !email(value.contact_email))
    fail("payload_invalid", 503);
  try {
    const codes = JSON.parse(value.reason_codes);
    if (
      !Array.isArray(codes) ||
      codes.length > 20 ||
      codes.some(
        (code) => typeof code !== "string" || !/^[-a-z0-9_]{1,64}$/.test(code),
      )
    )
      fail("payload_invalid", 503);
  } catch {
    fail("payload_invalid", 503);
  }
  return value;
}
export async function readRow(env, row, { allowUnconfirmed = false } = {}) {
  if (!row) return null;
  await requireRetention(env, row, {
    screened: row.status === "screened" && !allowUnconfirmed,
  });
  if (!isID(row.payload_id)) fail("payload_unavailable", 503);
  const tracked = await env.DB.prepare(
    "SELECT * FROM payload_generations WHERE id=? AND submission_id=?",
  )
    .bind(row.payload_id, row.id)
    .first();
  if (
    !tracked ||
    !isHash(tracked.sha256) ||
    !Number.isSafeInteger(tracked.bytes) ||
    tracked.bytes < 1 ||
    tracked.bytes > MAX_PAYLOAD
  )
    fail("payload_unavailable", 503);
  const object = await env.RAW.get(payloadKey(row.id, row.payload_id));
  if (!object || object.size !== tracked.bytes)
    fail("payload_unavailable", 503);
  const bytes = new Uint8Array(await object.arrayBuffer());
  if (
    bytes.length !== tracked.bytes ||
    (await digest(bytes)) !== tracked.sha256
  )
    fail("payload_invalid", 503);
  let record;
  try {
    record = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
  } catch {
    fail("payload_invalid", 503);
  }
  if (
    !record ||
    record.version !== 1 ||
    record.submissionID !== row.id ||
    Object.keys(record).some(
      (key) => !["version", "submissionID", "content"].includes(key),
    )
  )
    fail("payload_invalid", 503);
  const latest = await requireRetention(env, row, {
    screened: row.status === "screened" && !allowUnconfirmed,
  });
  return {
    ...row,
    ...content(record.content),
    expires_at: Math.min(row.expires_at, latest.expiresAt),
    _db_expires_at: row.expires_at,
    _retention: latest,
  };
}
export async function stagePayload(env, row, patch) {
  await requireRetention(env, row);
  if (row.payload_id && !PRIVATE_FIELDS.every((key) => Object.hasOwn(row, key)))
    fail("payload_unavailable", 503);
  if (Object.keys(patch).some((key) => !PRIVATE_FIELDS.includes(key)))
    fail("payload_invalid", 503);
  const fields = content({
    ...defaults,
    ...Object.fromEntries(
      PRIVATE_FIELDS.filter((key) => row[key] !== undefined).map((key) => [
        key,
        row[key],
      ]),
    ),
    ...patch,
  });
  const text = JSON.stringify({
      version: 1,
      submissionID: row.id,
      content: fields,
    }),
    data = new TextEncoder().encode(text);
  if (data.length > MAX_PAYLOAD) fail("payload_invalid", 503);
  const id = crypto.randomUUID(),
    sha256 = await digest(data),
    key = payloadKey(row.id, id);
  const tracked = await env.DB.prepare(
    "INSERT INTO payload_generations(id,submission_id,sha256,bytes,created_at) SELECT ?,?,?,?,? WHERE EXISTS(SELECT 1 FROM submissions WHERE id=? AND expires_at>?) RETURNING id",
  )
    .bind(id, row.id, sha256, data.length, now(), row.id, now())
    .first();
  if (!tracked) fail("payload_changed", 409);
  let stored = false;
  try {
    const written = await env.RAW.put(key, data, {
      onlyIf: { etagDoesNotMatch: "*" },
      httpMetadata: { contentType: "application/json" },
      customMetadata: {
        submission: row.id,
        expiresAt: String(row.created_at + LIMITS.heldDays * 86400),
      },
    });
    if (!written) fail("payload_changed", 409);
    stored = true;
    await requireRetention(env, row);
  } catch (error) {
    if (stored)
      try {
        await env.RAW.delete(key);
      } catch {}
    throw error;
  }
  return { id, content: fields };
}
export async function commitPayload(
  env,
  row,
  patch,
  { metadata: changes = {}, expected = {}, lease = false, beforeCommit } = {},
) {
  if (
    [...Object.keys(changes), ...Object.keys(expected)].some(
      (key) => !META_FIELDS.has(key),
    )
  )
    fail("payload_invalid", 503);
  const reviewDeadline =
    Object.hasOwn(expected, "review_expires_at") &&
    expected.review_expires_at !== null;
  const staged = await stagePayload(env, row, patch),
    sets = ["payload_id=?", ...Object.keys(changes).map((key) => `${key}=?`)],
    setArgs = [staged.id, ...Object.values(changes)],
    whereArgs = () => [
      row.id,
      row.payload_id ?? null,
      ...Object.values(expected),
      now(),
      ...(lease ? [now()] : []),
      ...(reviewDeadline ? [now()] : []),
    ];
  let where =
    "id=? AND payload_id IS ?" +
    Object.keys(expected)
      .map((key) => ` AND ${key} IS ?`)
      .join("") +
    " AND expires_at>?";
  if (lease) {
    where += " AND scan_lease_until>?";
  }
  if (reviewDeadline) where += " AND review_expires_at>?";
  if (beforeCommit) {
    const current = await env.DB.prepare(
      `SELECT id FROM submissions WHERE ${where}`,
    )
      .bind(...whereArgs())
      .first();
    if (!current) return null;
    await beforeCommit();
  }
  const changed = await env.DB.prepare(
    `UPDATE submissions SET ${sets.join(",")} WHERE ${where} RETURNING id`,
  )
    .bind(...setArgs, ...whereArgs())
    .first();
  if (!changed) return null;
  return { ...row, ...staged.content, ...changes, payload_id: staged.id };
}
