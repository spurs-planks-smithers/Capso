import { CLASSIFIER_REVISION, validateScan, fail } from "./policy.js";
import { nowSeconds } from "./store.js";
import { TEXT_MODEL, IMAGE_MODEL, MODEL_CONTRACT_VERSION } from "./models.js";
export const COMBINED_POLICY = `scanner:1;context:${MODEL_CONTRACT_VERSION};text:${TEXT_MODEL};vision:${IMAGE_MODEL};classifier:${CLASSIFIER_REVISION}`;
export const SCANNER_SOFT_REASONS = Object.freeze([
  "sensitive_credentials",
  "sensitive_government_id",
  "sensitive_payment",
  "sensitive_private_record",
  "prompt_injection",
  "hidden_control_text",
]);
export const SOFT_REASONS = Object.freeze([
  ...new Set([...SCANNER_SOFT_REASONS, "private_record", "credential"]),
]);
export const softReasons = (codes) =>
  Array.isArray(codes) &&
  codes.length > 0 &&
  codes.length <= SOFT_REASONS.length &&
  codes.every((code) => SOFT_REASONS.includes(code));
function parse(value) {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}
export function activeApproval(row, now = nowSeconds()) {
  const approval = parse(row.approval_json);
  if (
    !approval ||
    approval.version !== 1 ||
    approval.fingerprint !== row.fingerprint ||
    approval.policy !== COMBINED_POLICY ||
    approval.actor !== "drewschulz1@gmail.com" ||
    typeof approval.subject !== "string" ||
    !approval.subject ||
    !Number.isSafeInteger(approval.at) ||
    approval.at > now ||
    !Number.isSafeInteger(approval.expiresAt) ||
    approval.expiresAt <= now ||
    approval.expiresAt > row.expires_at ||
    approval.expiresAt > approval.at + 86400 ||
    !softReasons(approval.reasons) ||
    new Set(approval.reasons).size !== approval.reasons.length
  )
    return [];
  return approval.reasons;
}
export function inspectableReview(row, now = nowSeconds()) {
  if (
    row.status !== "held" ||
    row.review_fingerprint !== row.fingerprint ||
    row.review_policy !== COMBINED_POLICY ||
    !Number.isSafeInteger(row.review_expires_at) ||
    row.review_expires_at <= now ||
    row.review_expires_at > row.expires_at ||
    !softReasons(parse(row.reason_codes))
  )
    return false;
  const proof = parse(row.review_proof);
  if (
    !proof ||
    proof.hardChecksPassed !== true ||
    proof.contextChecksCompleted !== true ||
    proof.scanClaim !== row.scan_claim
  )
    return false;
  try {
    validateScan(
      {
        version: 1,
        status: "passed",
        reasonCodes: [],
        text: "",
        inspectionText: "",
        images: [],
        scan: proof.scan,
      },
      now * 1000,
    );
    return true;
  } catch {
    return false;
  }
}
export function approveReasons(row, codes, actor, now = nowSeconds()) {
  if (
    actor.email !== "drewschulz1@gmail.com" ||
    typeof actor.sub !== "string" ||
    !actor.sub ||
    actor.sub.length > 255 ||
    !inspectableReview(row, now) ||
    !softReasons(codes) ||
    new Set(codes).size !== codes.length
  )
    fail("approval_not_permitted", 409);
  const current = parse(row.reason_codes);
  if (
    current.length !== codes.length ||
    !current.every((code) => codes.includes(code))
  )
    fail("select_current_findings", 409);
  const reasons = [...new Set([...activeApproval(row, now), ...codes])].sort();
  return {
    version: 1,
    actor: actor.email,
    subject: actor.sub,
    at: now,
    expiresAt: Math.min(row.expires_at, now + 86400),
    fingerprint: row.fingerprint,
    policy: COMBINED_POLICY,
    reasons,
  };
}
export const findingLabel = (code) =>
  ({
    sensitive_credentials: "Credentials",
    credential: "Credentials",
    sensitive_government_id: "Government identifiers",
    sensitive_payment: "Payment details",
    sensitive_private_record: "Private records",
    private_record: "Private records",
    prompt_injection: "Prompt injection warning",
    hidden_control_text: "Hidden text controls",
  })[code] || "Screening needs attention";
export function reviewCandidate(result) {
  if (
    result.status !== "held" ||
    !softReasons(result.reasonCodes) ||
    !result.review ||
    result.review.hardChecksPassed !== true
  )
    return null;
  const { hardChecksPassed, ...candidate } = result.review;
  if (candidate.status !== "passed") return null;
  return validateScan(candidate);
}
