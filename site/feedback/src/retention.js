import { LIMITS, fail, isID } from "./policy.js";
const now = () => Math.floor(Date.now() / 1000);
const markerKey = (id) => `retention/${id}.json`;
const prefixID = /^([a-f0-9-]{36})\//;
function valid(marker, id) {
  if (
    !marker ||
    marker.version !== 1 ||
    marker.submissionID !== id ||
    !isID(id) ||
    !isID(marker.revision) ||
    !Number.isSafeInteger(marker.createdAt) ||
    !Number.isSafeInteger(marker.expiresAt) ||
    !["held", "screened", "expired"].includes(marker.phase)
  )
    fail("retention_unavailable", 503);
  if (
    ![
      marker.createdAt + LIMITS.heldDays * 86400,
      marker.createdAt + LIMITS.screenedDays * 86400,
    ].includes(marker.expiresAt)
  )
    fail("retention_unavailable", 503);
  if (
    marker.phase === "held" &&
    marker.expiresAt !== marker.createdAt + LIMITS.heldDays * 86400
  )
    fail("retention_unavailable", 503);
  if (
    marker.phase === "screened" &&
    (!isID(marker.screenedClaim) || !isID(marker.payloadID))
  )
    fail("retention_unavailable", 503);
  return marker;
}
export async function markerByID(env, id) {
  if (!isID(id)) fail("retention_unavailable", 503);
  const object = await env.RAW.get(markerKey(id));
  if (!object) return null;
  if (object.size > 2048) fail("retention_unavailable", 503);
  let marker;
  try {
    marker = JSON.parse(await object.text());
  } catch {
    fail("retention_unavailable", 503);
  }
  return { ...valid(marker, id), etag: object.etag };
}
export async function createRetention(env, id, createdAt) {
  const marker = {
    version: 1,
    submissionID: id,
    createdAt,
    expiresAt: createdAt + LIMITS.heldDays * 86400,
    phase: "held",
    revision: crypto.randomUUID(),
    screenedClaim: null,
    payloadID: null,
  };
  const result = await env.RAW.put(markerKey(id), JSON.stringify(marker), {
    onlyIf: { etagDoesNotMatch: "*" },
    httpMetadata: { contentType: "application/json" },
  });
  if (!result) fail("retention_conflict", 503);
  return { ...marker, etag: result.etag };
}
export async function requireRetention(env, row, { screened = false } = {}) {
  const marker = await markerByID(env, row.id);
  if (!marker || marker.createdAt !== row.created_at)
    fail("retention_unavailable", 503);
  if (
    marker.phase === "expired" ||
    Math.min(row.expires_at, marker.expiresAt) <= now()
  )
    fail("submission_expired", 410);
  if (
    screened &&
    (row.scan_lease_until !== null ||
      marker.phase !== "screened" ||
      marker.screenedClaim !== row.scan_claim ||
      marker.payloadID !== row.payload_id)
  )
    fail("publication_unconfirmed", 503);
  return marker;
}
async function changeMarker(
  env,
  row,
  captured,
  phase,
  claim = null,
  payloadID = null,
) {
  if (
    !captured ||
    typeof captured.etag !== "string" ||
    !captured.etag ||
    captured.submissionID !== row.id ||
    captured.createdAt !== row.created_at ||
    captured.phase === "expired" ||
    captured.expiresAt <= now()
  )
    fail("retention_unavailable", 503);
  const marker = {
    version: 1,
    submissionID: row.id,
    createdAt: captured.createdAt,
    expiresAt:
      captured.createdAt +
      (phase === "screened" ? LIMITS.screenedDays : LIMITS.heldDays) * 86400,
    phase,
    revision: crypto.randomUUID(),
    screenedClaim: phase === "screened" ? claim : null,
    payloadID: phase === "screened" ? payloadID : null,
  };
  let result;
  try {
    result = await env.RAW.put(markerKey(row.id), JSON.stringify(marker), {
      onlyIf: { etagMatches: captured.etag },
      httpMetadata: { contentType: "application/json" },
    });
  } catch (error) {
    const current = await markerByID(env, row.id);
    if (current?.revision === marker.revision) return current;
    throw error;
  }
  if (!result) fail("retention_conflict", 503);
  return { ...marker, etag: result.etag };
}
export const markHeld = (env, row, captured) =>
  changeMarker(env, row, captured, "held");
export async function markScreened(env, row, captured) {
  const owns = () =>
    env.DB.prepare(
      "SELECT id FROM submissions WHERE id=? AND status='screened' AND scan_claim=? AND payload_id=? AND scan_lease_until>? AND expires_at>?",
    )
      .bind(row.id, row.scan_claim, row.payload_id, now(), now())
      .first();
  if (!(await owns())) fail("scan_replaced", 409);
  const changed = await changeMarker(
    env,
    row,
    captured,
    "screened",
    row.scan_claim,
    row.payload_id,
  );
  if (captured.expiresAt <= now() || !(await owns())) {
    try {
      await changeMarker(env, row, changed, "held");
    } catch {
      /* Reads require a completed SQL publication even if rollback is unavailable. */
    }
    fail("scan_replaced", 409);
  }
  return changed;
}
async function deletePrefix(bucket, prefix) {
  let cursor;
  do {
    const page = await bucket.list({ prefix, cursor, limit: 1000 });
    if (page.objects.length)
      await bucket.delete(page.objects.map((object) => object.key));
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
}
export async function purgeRetention(env) {
  let cursor;
  const deleted = [];
  do {
    const page = await env.RAW.list({
      prefix: "retention/",
      cursor,
      limit: 1000,
    });
    for (const object of page.objects) {
      const id = object.key.slice("retention/".length, -".json".length);
      if (!isID(id)) continue;
      let marker = await markerByID(env, id);
      if (!marker) continue;
      const row = await env.DB.prepare(
        "SELECT expires_at FROM submissions WHERE id=?",
      )
        .bind(id)
        .first();
      if (
        Math.min(marker.expiresAt, row?.expires_at ?? marker.expiresAt) >
          now() &&
        marker.phase !== "expired"
      )
        continue;
      if (marker.phase !== "expired") {
        const expired = {
          ...marker,
          phase: "expired",
          revision: crypto.randomUUID(),
        };
        delete expired.etag;
        const changed = await env.RAW.put(
          markerKey(id),
          JSON.stringify(expired),
          {
            onlyIf: { etagMatches: marker.etag },
            httpMetadata: { contentType: "application/json" },
          },
        );
        if (!changed) continue;
      }
      await deletePrefix(env.RAW, `${id}/`);
      await deletePrefix(env.RAW, `payloads/${id}/`);
      await deletePrefix(env.REBUILT, `${id}/`);
      await env.DB.batch(
        [
          "audit",
          "derivatives",
          "upload_attempts",
          "files",
          "payload_generations",
        ]
          .map((table) =>
            env.DB.prepare(`DELETE FROM ${table} WHERE submission_id=?`).bind(
              id,
            ),
          )
          .concat([
            env.DB.prepare("DELETE FROM submissions WHERE id=?").bind(id),
          ]),
      );
      await env.RAW.delete(markerKey(id));
      deleted.push(id);
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return deleted.length;
}
// The cursor contains object identifiers only. It never contains submitted text.
export async function sweepOrphans(env, bucket, name) {
  const cursorKey = `_system/orphan-cursor-${name}.json`,
    stored = await env.RAW.get(cursorKey);
  let cursor;
  if (stored && stored.size < 8192) {
    try {
      cursor = JSON.parse(await stored.text()).cursor;
    } catch {}
  }
  const page = await bucket.list({ cursor, limit: 1000 }),
    markers = new Map();
  for (const object of page.objects) {
    const path = object.key.startsWith("payloads/")
      ? object.key.slice(9)
      : object.key;
    const id = path.match(prefixID)?.[1];
    if (!isID(id)) continue;
    if (!markers.has(id)) markers.set(id, await markerByID(env, id));
    const marker = markers.get(id);
    if (!marker || marker.phase === "expired" || marker.expiresAt <= now())
      await bucket.delete(object.key);
  }
  if (page.truncated)
    await env.RAW.put(cursorKey, JSON.stringify({ cursor: page.cursor }), {
      httpMetadata: { contentType: "application/json" },
    });
  else await env.RAW.delete(cursorKey);
}
