import { environment, rawFileCount } from "./fixture.js";
import { submission } from "../src/store.js";
import { commitPayload } from "../src/payload.js";
import test from "node:test";
import assert from "node:assert/strict";
import { api } from "../src/api.js";
import { processSubmission, maintenance } from "../src/pipeline.js";
import {
  purgeExpired,
  query,
  reserveBudget,
  nowSeconds,
} from "../src/store.js";
import { digest, CLASSIFIER_REVISION } from "../src/policy.js";
import { review } from "../src/review.js";
const request = (path, method = "GET", value, token) =>
  new Request(`https://feedback.nextshot.dev${path}`, {
    method,
    headers: {
      "CF-Connecting-IP": "192.0.2.1",
      ...(value && !(value instanceof Uint8Array)
        ? { "Content-Type": "application/json" }
        : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(value !== undefined
      ? { body: value instanceof Uint8Array ? value : JSON.stringify(value) }
      : {}),
  });
async function reserve(env, data = []) {
  const payload = {
    source: "native",
    category: "bug",
    message: "Save stays disabled.",
    idempotencyKey: crypto.randomUUID(),
    files: await Promise.all(
      data.map(async (bytes, n) => ({
        name: `capture-${n}.png`,
        bytes: bytes.length,
        sha256: await digest(bytes),
        contentType: "image/png",
      })),
    ),
  };
  const response = await api(request("/v1/reservations", "POST", payload), env);
  assert.equal(response.status, 201);
  return { payload, receipt: await response.json() };
}
async function finish(env, receipt, data = []) {
  for (let n = 0; n < data.length; n++) {
    const res = await api(
      request(
        `/v1/submissions/${receipt.id}/files/${receipt.uploads[n].id}`,
        "PUT",
        data[n],
        receipt.token,
      ),
      env,
    );
    assert.equal(res.status, 200);
  }
  const res = await api(
    request(
      `/v1/submissions/${receipt.id}/complete`,
      "POST",
      undefined,
      receipt.token,
    ),
    env,
  );
  assert.equal(res.status, 202);
}
const passed = (text) => ({
  version: 1,
  status: "passed",
  reasonCodes: [],
  text,
  inspectionText: text,
  images: [],
  scan: {
    engine: "ClamAV",
    definitionsAt: new Date().toISOString(),
    classifierRevision: CLASSIFIER_REVISION,
    policyVersion: "1",
  },
});
test("a complete native sequence can replay after a lost completion response without reopening files", async (t) => {
  const env = environment();
  t.after(env.close);
  const data = [new Uint8Array([1, 2, 3]), new Uint8Array([4, 5])],
    { payload, receipt } = await reserve(env, data);
  await finish(env, receipt, data);
  const before = Array.from(env.RAW.data.values(), (v) => Array.from(v));
  const replay = await api(request("/v1/reservations", "POST", payload), env);
  assert.equal(replay.status, 200);
  assert.deepEqual(await replay.json(), receipt);
  await finish(env, receipt, data);
  assert.deepEqual(
    Array.from(env.RAW.data.values(), (v) => Array.from(v)),
    before,
  );
  assert.equal(env.JOBS.sent.length, 1);
});
test("a changed idempotency payload and wrong upload bytes cannot replace a reservation", async (t) => {
  const env = environment();
  t.after(env.close);
  const data = [new Uint8Array([1, 2, 3])],
    { payload, receipt } = await reserve(env, data);
  assert.equal(
    (
      await api(
        request("/v1/reservations", "POST", { ...payload, message: "changed" }),
        env,
      )
    ).status,
    409,
  );
  assert.equal(
    (
      await api(
        request(
          `/v1/submissions/${receipt.id}/files/${receipt.uploads[0].id}`,
          "PUT",
          new Uint8Array([9, 9, 9]),
          receipt.token,
        ),
        env,
      )
    ).status,
    422,
  );
  assert.equal(rawFileCount(env), 0);
  assert.equal(
    (
      await api(
        request(
          `/v1/submissions/${receipt.id}/complete`,
          "POST",
          undefined,
          receipt.token,
        ),
        env,
      )
    ).status,
    409,
  );
});
test("shared native admission rejects the sixth hourly submission even with spoofed app headers", async (t) => {
  const env = environment();
  t.after(env.close);
  for (let n = 0; n < 5; n++) await reserve(env);
  const payload = {
    source: "native",
    category: "other",
    message: "Question",
    idempotencyKey: crypto.randomUUID(),
    files: [],
  };
  const res = await api(request("/v1/reservations", "POST", payload), env);
  assert.equal(res.status, 429);
});
test("website messages require server Turnstile and a native source cannot skip its own launch gate", async (t) => {
  const env = environment();
  t.after(env.close);
  const payload = {
    source: "web",
    category: "other",
    message: "Question",
    idempotencyKey: crypto.randomUUID(),
    files: [],
  };
  assert.equal(
    (await api(request("/v1/reservations", "POST", payload), env)).status,
    403,
  );
  env.NATIVE_ENABLED = "false";
  assert.equal(
    (
      await api(
        request("/v1/reservations", "POST", { ...payload, source: "native" }),
        env,
      )
    ).status,
    503,
  );
});
test("scanner outages and incomplete model checks keep text and originals out of Gmail", async (t) => {
  const env = environment();
  t.after(env.close);
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  await processSubmission(env, receipt.id, async () => {
    throw new Error("scanner unavailable");
  });
  const row = await submission(env, receipt.id);
  assert.equal(row.status, "held");
  assert.equal(env.notices.length, 0);
  assert.equal(env.REBUILT.data.size, 0);
  const status = await api(
    request(`/v1/submissions/${receipt.id}`, "GET", undefined, receipt.token),
    env,
  );
  assert.deepEqual(await status.json(), { id: receipt.id, status: "held" });
});
test("budget exhaustion stops processing before a scanner call", async (t) => {
  const env = environment();
  t.after(env.close);
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  await reserveBudget(env, 35000000);
  let calls = 0;
  await processSubmission(env, receipt.id, async () => {
    calls++;
    return passed("text");
  });
  assert.equal(calls, 0);
  assert.equal(
    (
      await query(
        env,
        "SELECT status FROM submissions WHERE id=?",
        receipt.id,
      ).first()
    ).status,
    "held",
  );
});
test("completed screening permits reconstructed text only and suppresses malformed issue drafts", async (t) => {
  const env = environment();
  t.after(env.close);
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  await processSubmission(env, receipt.id, async () =>
    passed("Save stays disabled."),
  );
  const row = await submission(env, receipt.id);
  assert.equal(row.status, "screened");
  assert.equal(row.draft_status, "held");
  assert.equal(env.notices.length, 1);
  assert.equal(env.notices[0].to, "drewschulz1@gmail.com");
  assert.equal(env.notices[0].html, undefined);
  assert.equal(env.notices[0].attachments, undefined);
  assert.match(env.notices[0].text, /Save stays disabled/);
});
test("owner routes fail closed without Access configuration or valid identity", async (t) => {
  const env = environment();
  t.after(env.close);
  assert.equal((await review(request("/review"), env)).status, 503);
  env.ACCESS_TEAM_DOMAIN = "team.cloudflareaccess.com";
  env.ACCESS_AUD = "audience";
  assert.equal((await review(request("/review"), env)).status, 401);
});
test("expiration removes originals, rebuilt files, content, drafts, and audit rows together", async (t) => {
  const env = environment();
  t.after(env.close);
  const data = [new Uint8Array([1, 2, 3])],
    { receipt } = await reserve(env, data);
  await finish(env, receipt, data);
  await query(
    env,
    "INSERT INTO derivatives(id,submission_id,name,storage_key,bytes,sha256) VALUES(?,?,?,?,?,?)",
    crypto.randomUUID(),
    receipt.id,
    "capture-1.jpg",
    `${receipt.id}/rebuilt-key`,
    3,
    "a".repeat(64),
  ).run();
  await env.REBUILT.put(`${receipt.id}/rebuilt-key`, data[0]);
  await query(
    env,
    "INSERT INTO audit(submission_id,action,at) VALUES(?,?,?)",
    receipt.id,
    "read",
    nowSeconds(),
  ).run();
  await query(
    env,
    "UPDATE submissions SET expires_at=? WHERE id=?",
    nowSeconds() - 1,
    receipt.id,
  ).run();
  assert.equal(await purgeExpired(env), 1);
  assert.equal(env.RAW.data.size, 0);
  assert.equal(env.REBUILT.data.size, 0);
  assert.equal(await submission(env, receipt.id), null);
  assert.equal(
    (await query(env, "SELECT * FROM audit").all()).results.length,
    0,
  );
});

test("an upload interrupted before storage recovers on explicit retry", async (t) => {
  const env = environment();
  t.after(env.close);
  const data = [new Uint8Array([1, 2, 3])],
    { receipt } = await reserve(env, data);
  await query(
    env,
    "UPDATE files SET status='uploading' WHERE id=?",
    receipt.uploads[0].id,
  ).run();
  await finish(env, receipt, data);
  assert.equal(
    (
      await query(
        env,
        "SELECT status FROM files WHERE id=?",
        receipt.uploads[0].id,
      ).first()
    ).status,
    "uploaded",
  );
});

test("an upload interrupted after storage verifies its original bytes before acknowledging retry", async (t) => {
  const env = environment();
  t.after(env.close);
  const data = [new Uint8Array([1, 2, 3])],
    { receipt } = await reserve(env, data);
  const file = await query(
    env,
    "SELECT * FROM files WHERE id=?",
    receipt.uploads[0].id,
  ).first();
  await env.RAW.put(file.raw_key, data[0]);
  await query(
    env,
    "UPDATE files SET status='uploading' WHERE id=?",
    file.id,
  ).run();
  await finish(env, receipt, data);
  assert.equal(rawFileCount(env), 1);
});

test("interrupted notification claims recover before send and after an uncertain send", async (t) => {
  const env = environment();
  t.after(env.close);
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  await processSubmission(env, receipt.id, async () =>
    passed("Screened feedback"),
  );
  env.notices.length = 0;
  await query(
    env,
    "UPDATE submissions SET notified=2 WHERE id=?",
    receipt.id,
  ).run();
  await maintenance(env);
  assert.equal(env.notices.length, 1);
  await query(
    env,
    "UPDATE submissions SET notified=2 WHERE id=?",
    receipt.id,
  ).run();
  await maintenance(env);
  assert.equal(env.notices.length, 2);
  assert.equal(
    (
      await query(
        env,
        "SELECT notified FROM submissions WHERE id=?",
        receipt.id,
      ).first()
    ).notified,
    1,
  );
});

test("owner inspection and exact approval rerun checks without forwarding held content or waiving draft output", async (t) => {
  const env = environment();
  t.after(env.close);
  const { generateKeyPair, exportJWK, SignJWT } = await import("jose");
  const { approveReasons } = await import("../src/approval.js");
  const { csrfToken } = await import("../src/access.js");
  const { publicKey, privateKey } = await generateKeyPair("RS256"),
    jwk = await exportJWK(publicKey);
  jwk.kid = "owner-review";
  jwk.alg = "RS256";
  env.ACCESS_TEAM_DOMAIN = "approval-flow.cloudflareaccess.com";
  env.ACCESS_AUD = "approval-audience";
  const jwt = await new SignJWT({ email: "drewschulz1@gmail.com" })
    .setProtectedHeader({ alg: "RS256", kid: jwk.kid })
    .setSubject("owner")
    .setIssuer("https://approval-flow.cloudflareaccess.com")
    .setAudience(env.ACCESS_AUD)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(privateKey);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    assert.equal(
      String(url),
      "https://approval-flow.cloudflareaccess.com/cdn-cgi/access/certs",
    );
    return new Response(JSON.stringify({ keys: [jwk] }));
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
  });
  const ownerRequest = (path, method = "GET", body) =>
    new Request(`https://feedback.nextshot.dev${path}`, {
      method,
      headers: {
        "Cf-Access-Jwt-Assertion": jwt,
        ...(body
          ? {
              Origin: "https://feedback.nextshot.dev",
              "Content-Type": "application/x-www-form-urlencoded",
            }
          : {}),
      },
      ...(body ? { body } : {}),
    });
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  const imageBytes = new Uint8Array([255, 216, 255, 217]);
  const image = {
    name: "capture-1.jpg",
    contentType: "image/jpeg",
    bodyBase64: btoa(String.fromCharCode(...imageBytes)),
    sha256: await digest(imageBytes),
  };
  const candidate = {
    ...passed("The public footer says Internal use only."),
    images: [image],
  };
  const jobs = [];
  env.AI.run = async (model, input) => ({
    response: JSON.stringify(
      input.messages?.[0]?.content?.startsWith("Prepare a private issue draft")
        ? {
            title: "Footer wording",
            category: "other",
            reported: "Footer wording is confusing.",
            requested: "Clarify the footer.",
            steps: [],
            severity: "sev-polish",
            captureReferences: ["capture-1.jpg"],
          }
        : { decision: "hold", reasons: ["private_record"] },
    ),
  });
  const scanner = async (_env, job) => {
    jobs.push(job);
    if (job.submission.message.startsWith("{"))
      return {
        version: 1,
        status: "held",
        reasonCodes: ["prompt_injection"],
        review: { ...passed(job.submission.message), hardChecksPassed: true },
      };
    return job.approvedReasons?.includes("sensitive_private_record")
      ? candidate
      : {
          version: 1,
          status: "held",
          reasonCodes: ["sensitive_private_record"],
          review: { ...candidate, hardChecksPassed: true },
        };
  };
  await processSubmission(env, receipt.id, scanner);
  let row = await submission(env, receipt.id);
  assert.equal(row.status, "held");
  assert.equal(env.notices.length, 0);
  assert.equal(row.draft_json, null);
  const file = await query(
    env,
    "SELECT * FROM derivatives WHERE submission_id=?",
    receipt.id,
  ).first();
  assert.equal(file.review_only, 1);
  assert.equal(
    (
      await review(
        new Request(
          `https://feedback.nextshot.dev/review/${receipt.id}/files/${file.id}`,
        ),
        env,
      )
    ).status,
    401,
  );
  assert.equal(
    (await review(ownerRequest(`/review/${receipt.id}/files/${file.id}`), env))
      .status,
    200,
  );
  assert.equal(
    (await review(ownerRequest(`/review/${receipt.id}/raw/${file.id}`), env))
      .status,
    404,
  );
  const page = await review(ownerRequest(`/review/${receipt.id}`), env);
  const html = await page.text();
  assert.match(html, /Approve as false positive/);
  assert.match(html, /Private records/);
  assert.doesNotMatch(html, /scanner:1;context:1/);
  const csrf = await csrfToken(env, "owner");
  const wrong = await review(
    ownerRequest(
      `/review/${receipt.id}/approve`,
      "POST",
      new URLSearchParams({ csrf, reasons: "credential" }),
    ),
    env,
  );
  assert.equal(wrong.status, 409);
  const codes = JSON.parse(row.reason_codes);
  const approved = await review(
    ownerRequest(
      `/review/${receipt.id}/approve`,
      "POST",
      new URLSearchParams({ csrf, reasons: codes.join(",") }),
    ),
    env,
  );
  assert.equal(approved.status, 303);
  row = await submission(env, receipt.id);
  assert.equal(row.status, "received");
  assert.equal(JSON.parse(row.approval_json).actor, "drewschulz1@gmail.com");
  await processSubmission(env, receipt.id, scanner);
  row = await submission(env, receipt.id);
  assert.equal(row.status, "screened");
  assert.equal(row.draft_status, "held");
  assert.equal(env.notices.length, 1);
  assert.ok(
    jobs.some((job) =>
      job.approvedReasons?.includes("sensitive_private_record"),
    ),
  );
  const draftJob = jobs.find((job) => job.submission.message.startsWith("{"));
  assert.equal(draftJob.approvedReasons, undefined);
});

test("a new finding and a hard failure remain held despite an earlier owner approval", async (t) => {
  const env = environment();
  t.after(env.close);
  const { approveReasons, inspectableReview } =
    await import("../src/approval.js");
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  const nested = {
    ...passed("Public footer wording."),
    hardChecksPassed: true,
  };
  await processSubmission(env, receipt.id, async () => ({
    version: 1,
    status: "held",
    reasonCodes: ["sensitive_private_record"],
    review: nested,
  }));
  let row = await submission(env, receipt.id);
  assert.equal(row.status, "held");
  const approval = approveReasons(row, JSON.parse(row.reason_codes), {
    email: "drewschulz1@gmail.com",
    sub: "owner",
  });
  await commitPayload(
    env,
    await submission(env, receipt.id),
    { approval_json: JSON.stringify(approval) },
    { metadata: { status: "received" } },
  );
  env.AI.run = async () => ({
    response: JSON.stringify({ decision: "hold", reasons: ["credential"] }),
  });
  await processSubmission(env, receipt.id, async () =>
    passed("Public footer wording."),
  );
  row = await submission(env, receipt.id);
  assert.equal(row.status, "held");
  assert.deepEqual(JSON.parse(row.reason_codes), ["credential"]);
  assert.equal(env.notices.length, 0);
  await query(
    env,
    "UPDATE submissions SET status='received' WHERE id=?",
    receipt.id,
  ).run();
  await processSubmission(env, receipt.id, async () => ({
    version: 1,
    status: "held",
    reasonCodes: ["scanner_unavailable"],
  }));
  row = await submission(env, receipt.id);
  assert.equal(row.status, "held");
  assert.equal(inspectableReview(row), false);
  assert.equal(row.review_proof, null);
  assert.equal(env.notices.length, 0);
});

test("unmatched or expired stored approval never enters a scanner job", async (t) => {
  const env = environment();
  t.after(env.close);
  const { COMBINED_POLICY } = await import("../src/approval.js");
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  const row = await submission(env, receipt.id);
  for (const changes of [
    { fingerprint: "changed" },
    { policy: "scanner:old" },
    { expiresAt: nowSeconds() - 1 },
  ]) {
    const approval = {
      version: 1,
      actor: "drewschulz1@gmail.com",
      subject: "owner",
      at: nowSeconds(),
      expiresAt: nowSeconds() + 3600,
      fingerprint: row.fingerprint,
      policy: COMBINED_POLICY,
      reasons: ["prompt_injection"],
      ...changes,
    };
    await commitPayload(
      env,
      await submission(env, receipt.id),
      { approval_json: JSON.stringify(approval) },
      { metadata: { status: "received" } },
    );
    let received;
    await processSubmission(env, receipt.id, async (_env, job) => {
      received = job;
      return {
        version: 1,
        status: "held",
        reasonCodes: ["scanner_unavailable"],
      };
    });
    assert.deepEqual(received.approvedReasons, []);
  }
});

test("active upload and notification leases are not reclaimed, and expired reservations cannot recover files", async (t) => {
  const env = environment();
  t.after(env.close);
  const data = [new Uint8Array([1, 2, 3])],
    { receipt } = await reserve(env, data),
    file = await query(
      env,
      "SELECT * FROM files WHERE id=?",
      receipt.uploads[0].id,
    ).first();
  await query(
    env,
    "UPDATE files SET status='uploading',upload_claim='active',upload_lease_until=? WHERE id=?",
    nowSeconds() + 120,
    file.id,
  ).run();
  assert.equal(
    (
      await api(
        request(
          `/v1/submissions/${receipt.id}/files/${file.id}`,
          "PUT",
          data[0],
          receipt.token,
        ),
        env,
      )
    ).status,
    409,
  );
  await env.RAW.put(file.raw_key, data[0]);
  await query(
    env,
    "UPDATE files SET upload_lease_until=? WHERE id=?",
    nowSeconds() - 1,
    file.id,
  ).run();
  await query(
    env,
    "UPDATE submissions SET reservation_expires_at=? WHERE id=?",
    nowSeconds() - 1,
    receipt.id,
  ).run();
  assert.equal(
    (
      await api(
        request(
          `/v1/submissions/${receipt.id}/files/${file.id}`,
          "PUT",
          data[0],
          receipt.token,
        ),
        env,
      )
    ).status,
    410,
  );
  await query(
    env,
    "UPDATE submissions SET status='screened',notified=2,notification_claim='active',notification_lease_until=? WHERE id=?",
    nowSeconds() + 300,
    receipt.id,
  ).run();
  await maintenance(env);
  assert.equal(env.notices.length, 0);
});

test("an expired scan cannot publish over a replacement scan or suppress its new hard finding", async (t) => {
  const env = environment();
  t.after(env.close);
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  let oldReady, newReady, finishOld, finishNew;
  const oldEntered = new Promise((resolve) => (oldReady = resolve)),
    newEntered = new Promise((resolve) => (newReady = resolve));
  const oldResult = new Promise((resolve) => (finishOld = resolve)),
    newResult = new Promise((resolve) => (finishNew = resolve));
  const oldProcess = processSubmission(env, receipt.id, async () => {
    oldReady();
    return oldResult;
  });
  await oldEntered;
  await query(
    env,
    "UPDATE submissions SET status='received',scan_lease_until=? WHERE id=?",
    nowSeconds() - 1,
    receipt.id,
  ).run();
  const replacement = processSubmission(env, receipt.id, async () => {
    newReady();
    return newResult;
  });
  await newEntered;
  finishOld(passed("Older clean result."));
  await oldProcess;
  const prematurelySent = env.notices.length;
  finishNew({
    version: 1,
    status: "held",
    reasonCodes: ["scanner_unavailable"],
  });
  await replacement;
  assert.equal(prematurelySent, 0);
  assert.equal(
    (
      await query(
        env,
        "SELECT status FROM submissions WHERE id=?",
        receipt.id,
      ).first()
    ).status,
    "held",
  );
  assert.equal(env.notices.length, 0);
});

test("a corrupt interrupted object is replaced immutably and every attempt expires", async (t) => {
  const env = environment();
  t.after(env.close);
  const data = [new Uint8Array([1, 2, 3])],
    { receipt } = await reserve(env, data);
  const before = await query(
    env,
    "SELECT * FROM files WHERE id=?",
    receipt.uploads[0].id,
  ).first();
  await env.RAW.put(before.raw_key, new Uint8Array([9, 9, 9]));
  await query(
    env,
    "UPDATE files SET status='uploading',upload_lease_until=? WHERE id=?",
    nowSeconds() - 1,
    before.id,
  ).run();
  await finish(env, receipt, data);
  const after = await query(
    env,
    "SELECT * FROM files WHERE id=?",
    before.id,
  ).first();
  assert.notEqual(after.raw_key, before.raw_key);
  assert.deepEqual(Array.from(env.RAW.data.get(before.raw_key)), [9, 9, 9]);
  await query(
    env,
    "UPDATE submissions SET expires_at=? WHERE id=?",
    nowSeconds() - 1,
    receipt.id,
  ).run();
  await purgeExpired(env);
  assert.equal(env.RAW.data.size, 0);
});

test("an upload completion cannot delete an object already adopted by recovery", async (t) => {
  const env = environment();
  t.after(env.close);
  const data = [new Uint8Array([1, 2, 3])],
    { receipt } = await reserve(env, data);
  const originalPut = env.RAW.put.bind(env.RAW),
    { recoverUpload } = await import("../src/uploads.js");
  env.RAW.put = async (key, body) => {
    await originalPut(key, body);
    await query(
      env,
      "UPDATE files SET upload_lease_until=? WHERE id=?",
      nowSeconds() - 1,
      receipt.uploads[0].id,
    ).run();
    const row = await submission(env, receipt.id),
      file = await query(
        env,
        "SELECT * FROM files WHERE id=?",
        receipt.uploads[0].id,
      ).first();
    assert.equal(await recoverUpload(env, row, file), true);
  };
  const result = await api(
    request(
      `/v1/submissions/${receipt.id}/files/${receipt.uploads[0].id}`,
      "PUT",
      data[0],
      receipt.token,
    ),
    env,
  );
  assert.equal(result.status, 200);
  const stored = await query(
    env,
    "SELECT * FROM files WHERE id=?",
    receipt.uploads[0].id,
  ).first();
  assert.ok(env.RAW.data.has(stored.raw_key));
});

test("a positive soft signal cannot hide a later required image-model failure", async (t) => {
  const env = environment();
  t.after(env.close);
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  const imageBytes = new Uint8Array([255, 216, 255, 217]),
    bodyBase64 = btoa(String.fromCharCode(...imageBytes)),
    sha256 = await digest(imageBytes);
  const candidate = {
    ...passed("Public footer."),
    images: [
      { name: "capture-1.jpg", contentType: "image/jpeg", bodyBase64, sha256 },
      { name: "capture-2.jpg", contentType: "image/jpeg", bodyBase64, sha256 },
    ],
  };
  let calls = 0;
  env.AI.run = async () => {
    calls++;
    if (calls === 3) throw new Error("image engine unavailable");
    return {
      response: JSON.stringify({
        decision: "hold",
        reasons: ["private_record"],
      }),
    };
  };
  await processSubmission(env, receipt.id, async () => ({
    version: 1,
    status: "held",
    reasonCodes: ["sensitive_private_record"],
    review: { ...candidate, hardChecksPassed: true },
  }));
  const row = await submission(env, receipt.id);
  assert.equal(calls, 3);
  assert.equal(row.status, "held");
  assert.equal(row.review_proof, null);
  assert.equal(env.REBUILT.data.size, 0);
  assert.equal(env.notices.length, 0);
});

test("a hard scanner failure cannot smuggle a review candidate into owner access", async (t) => {
  const env = environment();
  t.after(env.close);
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  await processSubmission(env, receipt.id, async () => ({
    version: 1,
    status: "held",
    reasonCodes: ["scanner_unavailable"],
    review: { ...passed("Untrusted candidate"), hardChecksPassed: true },
  }));
  const row = await submission(env, receipt.id);
  assert.equal(row.status, "held");
  assert.equal(row.review_proof, null);
  assert.equal(row.review_text, null);
  assert.equal(env.REBUILT.data.size, 0);
});

test("an unclaimed disabled worker cannot hold an active scan", async (t) => {
  const env = environment();
  t.after(env.close);
  const { hold } = await import("../src/store.js"),
    { receipt } = await reserve(env);
  await finish(env, receipt);
  await query(
    env,
    "UPDATE submissions SET status='scanning',scan_claim='active',scan_lease_until=? WHERE id=?",
    nowSeconds() + 180,
    receipt.id,
  ).run();
  await hold(env, receipt.id, ["processing_unavailable"]);
  assert.equal(
    (
      await query(
        env,
        "SELECT status FROM submissions WHERE id=?",
        receipt.id,
      ).first()
    ).status,
    "scanning",
  );
});

test("owner approval rejects review evidence replaced between validation and its atomic update", async (t) => {
  const { generateKeyPair, exportJWK, SignJWT } = await import("jose"),
    { csrfToken } = await import("../src/access.js");
  const { publicKey, privateKey } = await generateKeyPair("RS256"),
    jwk = await exportJWK(publicKey);
  jwk.kid = "review-cas";
  jwk.alg = "RS256";
  const issuer = "https://approval-cas.cloudflareaccess.com",
    audience = "approval-cas-audience";
  const jwt = await new SignJWT({ email: "drewschulz1@gmail.com" })
    .setProtectedHeader({ alg: "RS256", kid: jwk.kid })
    .setSubject("owner")
    .setIssuer(issuer)
    .setAudience(audience)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(privateKey);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    assert.equal(String(url), `${issuer}/cdn-cgi/access/certs`);
    return new Response(JSON.stringify({ keys: [jwk] }));
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
  });
  for (const changedField of [
    "scan_claim",
    "payload_id",
    "review_proof",
    "review_expires_at",
  ]) {
    const env = environment();
    t.after(env.close);
    env.ACCESS_TEAM_DOMAIN = "approval-cas.cloudflareaccess.com";
    env.ACCESS_AUD = audience;
    const { receipt } = await reserve(env);
    await finish(env, receipt);
    await processSubmission(env, receipt.id, async () => ({
      version: 1,
      status: "held",
      reasonCodes: ["sensitive_private_record"],
      review: { ...passed("Public license footer."), hardChecksPassed: true },
    }));
    const row = await submission(env, receipt.id),
      csrf = await csrfToken(env, "owner"),
      queuedBefore = env.JOBS.sent.length;
    const replacement = {
      scan_claim: crypto.randomUUID(),
      payload_id: "private payload replacement",
      review_proof: JSON.stringify({
        ...JSON.parse(row.review_proof),
        scan: {
          ...JSON.parse(row.review_proof).scan,
          definitionsAt: new Date(Date.now() - 1000).toISOString(),
        },
      }),
      review_expires_at: row.review_expires_at - 60,
    }[changedField];
    const prepare = env.DB.prepare;
    let replaced = false;
    env.DB.prepare = (sql) => {
      const statement = prepare(sql);
      if (!sql.startsWith("UPDATE submissions SET payload_id="))
        return statement;
      return {
        ...statement,
        bind(...args) {
          const bound = statement.bind(...args);
          return {
            ...bound,
            async first() {
              if (!replaced) {
                replaced = true;
                if (changedField === "payload_id") {
                  const interceptor = env.DB.prepare;
                  env.DB.prepare = prepare;
                  try {
                    assert.ok(
                      await commitPayload(env, row, {
                        reason_codes: '["prompt_injection"]',
                      }),
                    );
                  } finally {
                    env.DB.prepare = interceptor;
                  }
                } else
                  await prepare(
                    `UPDATE submissions SET ${changedField}=? WHERE id=?`,
                  )
                    .bind(replacement, receipt.id)
                    .run();
              }
              return bound.first();
            },
          };
        },
      };
    };
    const result = await review(
      new Request(
        `https://feedback.nextshot.dev/review/${receipt.id}/approve`,
        {
          method: "POST",
          headers: {
            "Cf-Access-Jwt-Assertion": jwt,
            Origin: "https://feedback.nextshot.dev",
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: new URLSearchParams({
            csrf,
            reasons: "sensitive_private_record",
          }),
        },
      ),
      env,
    );
    assert.equal(replaced, true);
    assert.equal(result.status, 409, changedField);
    assert.deepEqual(await result.json(), { error: "review_changed" });
    const current = await submission(env, receipt.id);
    assert.equal(current.status, "held");
    assert.equal(current.approval_json, null);
    assert.equal(env.JOBS.sent.length, queuedBefore);
  }
});
test("model-stage cost reservation fails closed before any model call", async (t) => {
  const env = environment();
  t.after(env.close);
  const { receipt } = await reserve(env);
  await finish(env, receipt);
  await reserveBudget(env, 34895000);
  let scannerCalls = 0,
    modelCalls = 0;
  env.AI.run = async () => {
    modelCalls++;
    throw new Error("must not run without a reservation");
  };
  await processSubmission(env, receipt.id, async () => {
    scannerCalls++;
    return passed("Ordinary text.");
  });
  assert.equal(scannerCalls, 1);
  assert.equal(modelCalls, 0);
  const row = await submission(env, receipt.id);
  assert.equal(row.status, "held");
  assert.deepEqual(JSON.parse(row.reason_codes), ["processing_budget"]);
});
