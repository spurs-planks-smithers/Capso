import { recoverExpiredUploads } from "./uploads.js";
import {
  enabled,
  LIMITS,
  fail,
  validateScan,
  toBase64,
  fromBase64,
  digest,
} from "./policy.js";
import {
  query,
  nowSeconds,
  submission,
  listFiles,
  reserveBudget,
  hold,
  enqueue,
  purgeExpired,
} from "./store.js";
import { contextualScreen, issueDraft } from "./models.js";
import {
  notifyScreened,
  notifyHeld,
  recoverNotificationClaims,
} from "./notify.js";
import {
  activeApproval,
  COMBINED_POLICY,
  SCANNER_SOFT_REASONS,
  softReasons,
  reviewCandidate,
} from "./approval.js";
async function renew(env, id, claim) {
  const now = nowSeconds(),
    owned = await query(
      env,
      "UPDATE submissions SET scan_lease_until=? WHERE id=? AND status='scanning' AND scan_claim=? AND scan_lease_until>? AND expires_at>? RETURNING id",
      now + 180,
      id,
      claim,
      now,
      now,
    ).first();
  if (!owned) fail("scan_replaced", 409);
}
async function beginScan(env, id, claim) {
  await renew(env, id, claim);
  // Keep prior generations tracked until expiration. A stale job never deletes a replacement's objects.
  await query(
    env,
    "UPDATE submissions SET review_text=NULL,review_proof=NULL,review_fingerprint=NULL,review_policy=NULL,review_expires_at=NULL WHERE id=? AND status='scanning' AND scan_claim=? AND scan_lease_until>?",
    id,
    claim,
    nowSeconds(),
  ).run();
}
async function storeImages(env, id, claim, images, reviewOnly) {
  for (const image of images) {
    await renew(env, id, claim);
    const data = fromBase64(image.bodyBase64);
    if ((await digest(data)) !== image.sha256) fail("rebuilt_mismatch", 503);
    const fileID = crypto.randomUUID(),
      key = `${id}/${claim}/${fileID}.jpg`;
    const inserted = await query(
      env,
      "INSERT INTO derivatives(id,submission_id,name,storage_key,bytes,sha256,review_only,scan_claim) SELECT ?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM submissions WHERE id=? AND status='scanning' AND scan_claim=? AND scan_lease_until>? AND expires_at>?) RETURNING id",
      fileID,
      id,
      image.name,
      key,
      data.length,
      image.sha256,
      reviewOnly ? 1 : 0,
      claim,
      id,
      claim,
      nowSeconds(),
      nowSeconds(),
    ).first();
    if (!inserted) fail("scan_replaced", 409);
    try {
      await env.REBUILT.put(key, data, {
        httpMetadata: { contentType: "image/jpeg" },
      });
      await renew(env, id, claim);
    } catch (error) {
      try {
        await env.REBUILT.delete(key);
      } catch {
        /* The tracked artifact is also removed by retention. */
      }
      throw error;
    }
  }
}
async function heldForReview(env, row, claim, candidate, reasons) {
  await storeImages(env, row.id, claim, candidate.images, true);
  await renew(env, row.id, claim);
  const expires = Math.min(
    row.created_at + LIMITS.heldDays * 86400,
    nowSeconds() + 86400,
    Math.floor(Date.parse(candidate.scan.definitionsAt) / 1000) +
      LIMITS.signaturesSeconds,
  );
  const stored = await query(
    env,
    "UPDATE submissions SET status='held',reason_codes=?,scan_metadata=?,review_text=?,review_proof=?,review_fingerprint=?,review_policy=?,review_expires_at=?,scan_lease_until=NULL,expires_at=MIN(expires_at,created_at+?) WHERE id=? AND status='scanning' AND scan_claim=? AND scan_lease_until>? AND expires_at>? RETURNING id",
    JSON.stringify(reasons),
    JSON.stringify(candidate.scan),
    candidate.text,
    JSON.stringify({
      hardChecksPassed: true,
      contextChecksCompleted: true,
      scanClaim: claim,
      scan: candidate.scan,
    }),
    row.fingerprint,
    COMBINED_POLICY,
    expires,
    LIMITS.heldDays * 86400,
    row.id,
    claim,
    nowSeconds(),
    nowSeconds(),
  ).first();
  if (!stored) fail("scan_replaced", 409);
}
export async function processSubmission(env, id, scan) {
  const row = await submission(env, id);
  if (!row || row.expires_at <= nowSeconds() || row.status !== "received")
    return;
  if (
    !enabled(env, "PROCESSING_ENABLED") ||
    !enabled(env, "AI_SCREENING_ENABLED")
  ) {
    await hold(env, id, ["processing_unavailable"]);
    return;
  }
  const claim = crypto.randomUUID(),
    lease = await query(
      env,
      "UPDATE submissions SET status='scanning',scan_claim=?,scan_lease_until=? WHERE id=? AND status='received' RETURNING id",
      claim,
      nowSeconds() + 180,
      id,
    ).first();
  if (!lease) return;
  const beforeCall = () => renew(env, id, claim);
  try {
    await beginScan(env, id, claim);
    const files = await listFiles(env, id);
    // Reserve a conservative charge before scanner and model calls. Unused reservations are not refunded.
    await reserveBudget(
      env,
      100000 +
        files.filter((f) => f.role !== "email-original").length * 25000 +
        (files.some((f) => f.content_type === "application/zip") ? 150000 : 0),
    );
    const inputs = [];
    for (const file of files) {
      await beforeCall();
      if (file.status !== "uploaded") fail("upload_missing", 503);
      const object = await env.RAW.get(file.raw_key);
      if (!object || object.size !== file.bytes) fail("upload_missing", 503);
      const data = new Uint8Array(await object.arrayBuffer());
      if ((await digest(data)) !== file.sha256) fail("upload_mismatch", 503);
      inputs.push({
        id: file.id,
        contentType: file.content_type,
        bodyBase64: toBase64(data),
        ...(file.role === "email-original" ? { role: "email-original" } : {}),
      });
    }
    const approved = activeApproval(row),
      job = {
        submission: {
          id,
          category: row.category,
          message: row.message,
          contactEmail: row.contact_email,
        },
        files: inputs,
        approvedReasons: approved.filter((code) =>
          SCANNER_SOFT_REASONS.includes(code),
        ),
      };
    await beforeCall();
    const result = validateScan(await scan(env, job));
    await beforeCall();
    const candidate =
      result.status === "passed" ? result : reviewCandidate(result);
    if (!candidate) {
      await hold(
        env,
        id,
        result.reasonCodes,
        result.status === "rejected" ? "rejected" : "held",
        claim,
      );
      return;
    }
    // Every contextual check completes even when one known soft signal is positive.
    const context = await contextualScreen(
      env,
      candidate.inspectionText,
      candidate.images,
      beforeCall,
    );
    await beforeCall();
    const currentApproved = activeApproval(row);
    if (
      approved.length &&
      approved.some((code) => !currentApproved.includes(code))
    ) {
      await hold(env, id, ["approval_expired"], "held", claim);
      return;
    }
    const findings = [
      ...new Set([
        ...(result.status === "held" ? result.reasonCodes : []),
        ...context.filter((code) => !currentApproved.includes(code)),
      ]),
    ];
    if (findings.length) {
      if (softReasons(findings))
        await heldForReview(env, row, claim, candidate, findings);
      else await hold(env, id, findings, "held", claim);
      return;
    }
    await storeImages(env, id, claim, candidate.images, false);
    let draft = null,
      draftStatus = "unavailable";
    try {
      const proposed = await issueDraft(
          env,
          candidate.text,
          candidate.images.map((image) => image.name),
          beforeCall,
        ),
        output = JSON.stringify(proposed);
      await beforeCall();
      // Draft output receives fresh checks without any owner waiver.
      const checked = validateScan(
        await scan(env, {
          submission: {
            id,
            category: row.category,
            message: output,
            contactEmail: "",
          },
          files: [],
        }),
      );
      await beforeCall();
      if (
        checked.status === "passed" &&
        (await contextualScreen(env, output, [], beforeCall)).length === 0
      ) {
        draft = proposed;
        draftStatus = "ready";
      } else draftStatus = "held";
    } catch (error) {
      if (error?.code === "scan_replaced") throw error;
      draftStatus = "held";
    }
    await beforeCall();
    if (
      approved.length &&
      approved.some((code) => !activeApproval(row).includes(code))
    ) {
      await hold(env, id, ["approval_expired"], "held", claim);
      return;
    }
    const published = await query(
      env,
      "UPDATE submissions SET status='screened',screened_text=?,draft_json=?,draft_status=?,scan_metadata=?,scan_lease_until=NULL,expires_at=created_at+? WHERE id=? AND status='scanning' AND scan_claim=? AND scan_lease_until>? AND expires_at>? RETURNING id",
      candidate.text,
      draft ? JSON.stringify(draft) : null,
      draftStatus,
      JSON.stringify(candidate.scan),
      LIMITS.screenedDays * 86400,
      id,
      claim,
      nowSeconds(),
      nowSeconds(),
    ).first();
    if (!published) fail("scan_replaced", 409);
    await notifyScreened(env, await submission(env, id));
  } catch (error) {
    if (error?.code === "scan_replaced") return;
    const codes = ["processing_budget", "stale_signatures"].includes(
      error?.code,
    )
      ? [error.code]
      : ["screening_incomplete"];
    await hold(env, id, codes, "held", claim);
  }
}
export async function maintenance(env) {
  await recoverNotificationClaims(env);
  await recoverExpiredUploads(env);
  await purgeExpired(env);
  await query(
    env,
    "UPDATE submissions SET status='held',reason_codes='[\"scan_interrupted\"]',scan_lease_until=NULL,review_text=NULL,review_proof=NULL,review_fingerprint=NULL,review_policy=NULL,review_expires_at=NULL,expires_at=MIN(expires_at,created_at+?) WHERE status='scanning' AND scan_lease_until<?",
    LIMITS.heldDays * 86400,
    nowSeconds(),
  ).run();
  if (enabled(env, "PROCESSING_ENABLED")) {
    const outbox = (
      await query(
        env,
        "SELECT id FROM submissions WHERE status='received' AND queued=0 AND expires_at>? LIMIT 20",
        nowSeconds(),
      ).all()
    ).results;
    for (const row of outbox) {
      try {
        await enqueue(env, row.id);
      } catch {
        break;
      }
    }
  }
  const notices = (
    await query(
      env,
      "SELECT * FROM submissions WHERE status='screened' AND notified=0 LIMIT 20",
    ).all()
  ).results;
  for (const row of notices) await notifyScreened(env, row);
  await notifyHeld(env);
}
