import test from "node:test";
import assert from "node:assert/strict";
import {
  activeApproval,
  inspectableReview,
  approveReasons,
  COMBINED_POLICY,
} from "../src/approval.js";
import { CLASSIFIER_REVISION } from "../src/policy.js";
const now = () => Math.floor(Date.now() / 1000);
const row = () => ({
  id: crypto.randomUUID(),
  status: "held",
  scan_claim: "proof-scan",
  fingerprint: "f".repeat(64),
  expires_at: now() + 86400,
  reason_codes: JSON.stringify(["sensitive_private_record"]),
  review_text: "Internal use only is the public license footer.",
  review_fingerprint: "f".repeat(64),
  review_policy: COMBINED_POLICY,
  review_expires_at: now() + 3600,
  review_proof: JSON.stringify({
    hardChecksPassed: true,
    contextChecksCompleted: true,
    scanClaim: "proof-scan",
    scan: {
      engine: "ClamAV",
      definitionsAt: new Date().toISOString(),
      classifierRevision: CLASSIFIER_REVISION,
      policyVersion: "1",
    },
  }),
});
test("owner approvals bind exact findings, fingerprint, policy, actor, and expiry", () => {
  const r = row();
  assert.equal(inspectableReview(r), true);
  const approval = approveReasons(r, ["sensitive_private_record"], {
    email: "drewschulz1@gmail.com",
    sub: "owner",
  });
  r.approval_json = JSON.stringify(approval);
  assert.deepEqual(activeApproval(r), ["sensitive_private_record"]);
  assert.deepEqual(activeApproval({ ...r, fingerprint: "changed" }), []);
  assert.deepEqual(
    activeApproval({
      ...r,
      approval_json: JSON.stringify({ ...approval, policy: "old" }),
    }),
    [],
  );
  assert.deepEqual(
    activeApproval({
      ...r,
      approval_json: JSON.stringify({ ...approval, expiresAt: now() - 1 }),
    }),
    [],
  );
  assert.throws(() =>
    approveReasons(r, ["credential"], {
      email: "drewschulz1@gmail.com",
      sub: "owner",
    }),
  );
  assert.throws(() =>
    approveReasons(r, ["sensitive_private_record"], {
      email: "attacker@example.com",
      sub: "other",
    }),
  );
});
test("hard failures, incomplete proof, uncertain content, and stale evidence cannot be approved or inspected", () => {
  for (const reason of [
    "malware",
    "scanner_unavailable",
    "uncertain",
    "prohibited_content",
    "stale_signatures",
    "text_limit",
  ]) {
    const r = { ...row(), reason_codes: JSON.stringify([reason]) };
    assert.equal(inspectableReview(r), false);
    assert.throws(() =>
      approveReasons(r, [reason], {
        email: "drewschulz1@gmail.com",
        sub: "owner",
      }),
    );
  }
  const r = row();
  assert.equal(
    inspectableReview({
      ...r,
      review_proof: JSON.stringify({
        hardChecksPassed: true,
        contextChecksCompleted: false,
      }),
    }),
    false,
  );
  assert.equal(
    inspectableReview({ ...r, review_expires_at: now() - 1 }),
    false,
  );
  assert.equal(
    inspectableReview({ ...r, review_fingerprint: "changed" }),
    false,
  );
});
