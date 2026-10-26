import { metadata, readRow, commitPayload } from "./payload.js";
import { requireRetention, markHeld, markScreened } from "./retention.js";
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
function engineProof(scan) {
  return {
    engine: "ClamAV",
    definitionsAt: new Date(Date.parse(scan.definitionsAt)).toISOString(),
    classifierRevision: scan.classifierRevision,
    policyVersion: "1",
  };
}
async function renew(env, id, claim) {
  const current = await metadata(env, id);
  if (!current) fail("scan_replaced", 409);
  await requireRetention(env, current);
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
    "UPDATE submissions SET review_proof=NULL,review_fingerprint=NULL,review_policy=NULL,review_expires_at=NULL WHERE id=? AND status='scanning' AND scan_claim=? AND scan_lease_until>?",
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
  const stored = await commitPayload(
    env,
    row,
    { reason_codes: JSON.stringify(reasons), review_text: candidate.text },
    {
      metadata: {
        status: "held",
        scan_metadata: JSON.stringify(engineProof(candidate.scan)),
        review_proof: JSON.stringify({
          hardChecksPassed: true,
          contextChecksCompleted: true,
          scanClaim: claim,
          scan: engineProof(candidate.scan),
        }),
        review_fingerprint: row.fingerprint,
        review_policy: COMBINED_POLICY,
        review_expires_at: expires,
        scan_lease_until: null,
        expires_at: Math.min(
          row.expires_at,
          row.created_at + LIMITS.heldDays * 86400,
        ),
      },
      expected: { status: "scanning", scan_claim: claim },
      lease: true,
      beforeCommit: () => markHeld(env, row, row._retention),
    },
  );
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
        row._retention,
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
      await hold(env, id, ["approval_expired"], "held", claim, row._retention);
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
      else await hold(env, id, findings, "held", claim, row._retention);
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
      await hold(env, id, ["approval_expired"], "held", claim, row._retention);
      return;
    }
    const published = await commitPayload(
      env,
      row,
      {
        screened_text: candidate.text,
        draft_json: draft ? JSON.stringify(draft) : null,
        review_text: null,
        reason_codes: "[]",
      },
      {
        metadata: {
          status: "screened",
          scan_claim: claim,
          draft_status: draftStatus,
          scan_metadata: JSON.stringify(engineProof(candidate.scan)),
          expires_at: row.created_at + LIMITS.screenedDays * 86400,
        },
        expected: { status: "scanning", scan_claim: claim },
        lease: true,
      },
    );
    if (!published) fail("scan_replaced", 409);
    const owned = await query(
      env,
      "SELECT id FROM submissions WHERE id=? AND status='screened' AND scan_claim=? AND payload_id=? AND scan_lease_until>?",
      id,
      claim,
      published.payload_id,
      nowSeconds(),
    ).first();
    if (!owned) fail("scan_replaced", 409);
    await markScreened(env, published, row._retention);
    const completed = await query(
      env,
      "UPDATE submissions SET scan_lease_until=NULL WHERE id=? AND status='screened' AND scan_claim=? AND payload_id=? AND scan_lease_until>? RETURNING id",
      id,
      claim,
      published.payload_id,
      nowSeconds(),
    ).first();
    if (!completed) fail("scan_replaced", 409);
    await notifyScreened(env, await submission(env, id));
  } catch (error) {
    if (error?.code === "scan_replaced") return;
    const codes = ["processing_budget", "stale_signatures"].includes(
      error?.code,
    )
      ? [error.code]
      : ["screening_incomplete"];
    try {
      await hold(env, id, codes, "held", claim, row._retention);
    } catch {
      /* Missing or expired R2 authority cannot publish content. */
    }
  }
}
export async function maintenance(env) {
  await recoverNotificationClaims(env);
  await recoverExpiredUploads(env);
  await purgeExpired(env);
  const interrupted = (
    await query(
      env,
      "SELECT * FROM submissions WHERE status IN ('scanning','screened') AND scan_lease_until IS NOT NULL AND scan_lease_until<? LIMIT 50",
      nowSeconds(),
    ).all()
  ).results;
  for (const raw of interrupted) {
    try {
      // Interrupted publication needs a full recheck. Metadata cannot prove a completed live lease.
      const row = await readRow(env, raw, { allowUnconfirmed: true });
      await commitPayload(
        env,
        row,
        { reason_codes: '["scan_interrupted"]', review_text: null },
        {
          metadata: {
            status: "held",
            scan_lease_until: null,
            review_proof: null,
            review_fingerprint: null,
            review_policy: null,
            review_expires_at: null,
            expires_at: Math.min(
              row.expires_at,
              row.created_at + LIMITS.heldDays * 86400,
            ),
          },
          expected: {
            status: raw.status,
            scan_claim: raw.scan_claim,
            scan_lease_until: raw.scan_lease_until,
          },
          beforeCommit: () => markHeld(env, row, row._retention),
        },
      );
    } catch {
      /* Expired or unavailable content cannot be restored from metadata. */
    }
  }
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
