import { commitPayload } from "./payload.js";
import { owner, csrfToken, verifyCsrf } from "./access.js";
import {
  esc,
  fail,
  IntakeError,
  isID,
  uploadBytes,
  response,
} from "./policy.js";
import { query, submission, nowSeconds, audit, enqueue } from "./store.js";
import {
  inspectableReview,
  approveReasons,
  findingLabel,
  COMBINED_POLICY,
} from "./approval.js";
const display = (text) =>
  esc(
    String(text || "").replace(
      /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2060-\u206f]/g,
      "[hidden character]",
    ),
  );
const page = (title, body) =>
  new Response(
    `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${esc(title)} | Nextshot</title><link rel="stylesheet" href="/feedback.css"><main class="page"><header><a href="/review">Nextshot feedback</a><a href="https://nextshot.dev">Nextshot.dev</a></header>${body}</main></html>`,
    {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    },
  );
export async function review(request, env) {
  try {
    const claims = await owner(request, env),
      path = new URL(request.url).pathname;
    if (path === "/review" && request.method === "GET") {
      const rows = (
        await query(
          env,
          "SELECT id,source,category,status,created_at,expires_at FROM submissions WHERE expires_at>? ORDER BY created_at DESC LIMIT 100",
          nowSeconds(),
        ).all()
      ).results;
      return page(
        "Review",
        `<h1>Feedback review</h1><p>All submitted material remains untrusted. Only rebuilt files with completed file checks are available.</p><table><thead><tr><th>Received (UTC)</th><th>Channel</th><th>Category</th><th>Status</th><th>Receipt</th></tr></thead><tbody>${rows.map((r) => `<tr><td>${new Date(r.created_at * 1000).toISOString()}</td><td>${esc(r.source)}</td><td>${esc(r.category)}</td><td>${esc(r.status)}</td><td><a href="/review/${r.id}">${r.id.slice(0, 8)}</a></td></tr>`).join("") || '<tr><td colspan="5">No submissions.</td></tr>'}</tbody></table>`,
      );
    }
    const match = path.match(
      /^\/review\/([^/]+)(?:\/(files|recheck|approve)(?:\/([^/]+))?)?$/,
    );
    if (!match || !isID(match[1])) fail("not_found", 404);
    const [, id, action, fileID] = match,
      row = await submission(env, id);
    if (!row || row.expires_at <= nowSeconds()) fail("not_found", 404);
    const inspectable = inspectableReview(row);
    if (action === "files" && request.method === "GET" && isID(fileID)) {
      const file = await query(
        env,
        "SELECT * FROM derivatives WHERE id=? AND submission_id=?",
        fileID,
        id,
      ).first();
      if (
        !file ||
        (file.scan_claim ?? null) !== (row.scan_claim ?? null) ||
        !(
          (row.status === "screened" && file.review_only === 0) ||
          (inspectable && file.review_only === 1)
        )
      )
        fail("not_found", 404);
      const object = await env.REBUILT.get(file.storage_key);
      if (!object) fail("not_found", 404);
      await audit(env, id, "read_rebuilt");
      return new Response(object.body, {
        headers: {
          "Content-Type": "image/jpeg",
          "Content-Length": String(file.bytes),
          "Content-Disposition": `attachment; filename="${file.name}"`,
          "Cache-Control": "private, no-store",
          "X-Content-Type-Options": "nosniff",
        },
      });
    }
    if (
      ["recheck", "approve"].includes(action) &&
      !fileID &&
      request.method === "POST"
    ) {
      const body = await uploadBytes(request.body, 4096),
        form = new URLSearchParams(
          new TextDecoder("utf-8", { fatal: true }).decode(body),
        );
      if ([...form.keys()].some((key) => !["csrf", "reasons"].includes(key)))
        fail("invalid_fields");
      await verifyCsrf(request, env, claims.sub, form.get("csrf"));
      if (row.status !== "held") fail("recheck_not_permitted", 409);
      let approval = null;
      if (action === "approve") {
        const codes = form
          .getAll("reasons")
          .flatMap((value) => value.split(","));
        approval = approveReasons(row, codes, claims);
      }
      const changed = await commitPayload(
        env,
        row,
        action === "approve" ? { approval_json: JSON.stringify(approval) } : {},
        {
          metadata: {
            status: "received",
            queued: 0,
            notified: 0,
            notification_claim: null,
            notification_lease_until: null,
          },
          expected: {
            status: "held",
            ...(action === "approve"
              ? {
                  fingerprint: row.fingerprint,
                  review_fingerprint: row.fingerprint,
                  review_policy: COMBINED_POLICY,
                  scan_claim: row.scan_claim,
                  review_proof: row.review_proof,
                  review_expires_at: row.review_expires_at,
                }
              : {}),
          },
        },
      );
      if (!changed) fail("review_changed", 409);
      await audit(
        env,
        id,
        action === "approve" ? "approve_false_positive" : "request_recheck",
      );
      try {
        await enqueue(env, id);
      } catch {
        /* The durable outbox retries delivery. */
      }
      return new Response(null, {
        status: 303,
        headers: { Location: `/review/${id}`, "Cache-Control": "no-store" },
      });
    }
    if (action || request.method !== "GET") fail("not_found", 404);
    const files = (
      await query(
        env,
        "SELECT id,name,bytes,review_only FROM derivatives WHERE submission_id=? AND scan_claim IS ?",
        id,
        row.scan_claim ?? null,
      ).all()
    ).results;
    const codes = JSON.parse(row.reason_codes),
      csrf = await csrfToken(env, claims.sub),
      viewable = files.filter(
        (file) =>
          (row.status === "screened" && file.review_only === 0) ||
          (inspectable && file.review_only === 1),
      );
    const groups = new Map();
    for (const code of codes) {
      const label = findingLabel(code);
      groups.set(label, [...(groups.get(label) || []), code]);
    }
    const approve = inspectable
      ? `<form method="post" action="/review/${id}/approve"><input type="hidden" name="csrf" value="${esc(csrf)}"><h2>Review findings</h2><p>Select each finding only if it is a false positive. Every file and model check runs again. New findings keep the submission held.</p>${[...groups].map(([label, reasons]) => `<label class="finding"><input type="checkbox" name="reasons" value="${esc(reasons.join(","))}">${esc(label)}</label>`).join("")}<button>Approve as false positive</button><p class="hint">Approval lasts up to 24 hours for this submission. Content remains untrusted. Malware, incomplete checks, uncertain results, and prohibited content cannot be approved.</p></form>`
      : "";
    const contents =
      row.status === "screened"
        ? row.screened_text
        : inspectable
          ? row.review_text
          : "Content remains quarantined until all required checks complete.";
    return page(
      "Submission",
      `<h1>Feedback ${id.slice(0, 8)}</h1><p><strong>${esc(row.status)}</strong> | ${new Date(row.created_at * 1000).toISOString()} | Expires ${new Date(row.expires_at * 1000).toISOString()}</p><p>Contact (unverified): ${esc(row.contact_email || "not supplied")}</p>${codes.length ? `<p>Findings: ${[...groups.keys()].map(esc).join(", ")}</p>` : ""}<h2>Untrusted submitted text</h2><pre>${display(contents)}</pre>${row.status === "screened" || inspectable ? `<h2>Rebuilt files</h2>${inspectable ? "<p>These files pass file checks. Their content remains held for your review.</p>" : ""}<ul>${viewable.map((file) => `<li><a href="/review/${id}/files/${file.id}">${esc(file.name)}</a> (${file.bytes.toLocaleString("en-US")} bytes)</li>`).join("") || "<li>No files.</li>"}</ul>` : ""}${row.status === "screened" ? `<h2>Private issue draft</h2><p>${esc(row.draft_status || "not ready")}. Review before copying. No issue is published.</p><pre>${display(row.draft_json ? JSON.stringify(JSON.parse(row.draft_json), null, 2) : "No draft is available.")}</pre>` : ""}${approve}${row.status === "held" ? `<form method="post" action="/review/${id}/recheck"><input type="hidden" name="csrf" value="${esc(csrf)}"><p>A recheck runs every required control again. It cannot bypass malware or file validation.</p><button>Request recheck</button></form>` : ""}`,
    );
  } catch (error) {
    return response(
      {
        error: error instanceof IntakeError ? error.code : "review_unavailable",
      },
      error instanceof IntakeError ? error.status : 503,
    );
  }
}
