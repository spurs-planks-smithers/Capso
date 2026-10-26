import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { environment } from "./fixture.js";
import { api } from "../src/api.js";
import { submission, purgeExpired, query, nowSeconds } from "../src/store.js";
import {
  metadata,
  commitPayload,
  payloadKey,
  PRIVATE_FIELDS,
} from "../src/payload.js";
import {
  markerByID,
  markHeld,
  purgeRetention,
  sweepOrphans,
} from "../src/retention.js";
import { processSubmission, maintenance } from "../src/pipeline.js";
import { notifyScreened } from "../src/notify.js";
import { digest, CLASSIFIER_REVISION } from "../src/policy.js";
const request = (path, method = "GET", body, token) =>
  new Request(`https://feedback.nextshot.dev${path}`, {
    method,
    headers: {
      "CF-Connecting-IP": "192.0.2.44",
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
async function submitted(env) {
  const body = {
    source: "native",
    category: "question",
    message: "Private fixture 8937: account question.",
    contactEmail: "private8937@example.com",
    idempotencyKey: crypto.randomUUID(),
    files: [],
  };
  const res = await api(request("/v1/reservations", "POST", body), env);
  assert.equal(res.status, 201);
  return { ...(await res.json()), body };
}
async function completed(env) {
  const receipt = await submitted(env);
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
  return receipt;
}
const passed = (text = "Screened fixture 8937.") => ({
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
function snapshot(env) {
  return env.sql
    .prepare(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    )
    .all()
    .map(({ name }) => ({
      name,
      rows: env.sql.prepare(`SELECT * FROM ${name}`).all(),
    }));
}
function restore(env, saved) {
  for (const { name } of [...saved].reverse())
    env.sql.exec(`DELETE FROM ${name}`);
  for (const { name, rows } of saved)
    for (const row of rows) {
      const keys = Object.keys(row);
      env.sql
        .prepare(
          `INSERT INTO ${name}(${keys.join(",")}) VALUES(${keys.map(() => "?").join(",")})`,
        )
        .run(...Object.values(row));
    }
}
test("D1 stores no submitted, screened, review, draft, approval, or finding content", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await submitted(env);
  let row = await submission(env, receipt.id);
  await commitPayload(env, row, {
    screened_text: "Screened fixture 8937.",
    review_text: "Review fixture 8937.",
    draft_json: '{"title":"Draft fixture 8937"}',
    approval_json: '{"actor":"Owner fixture 8937"}',
    reason_codes: '["sensitive_private_record"]',
  });
  row = await submission(env, receipt.id);
  const dump = JSON.stringify(snapshot(env));
  assert.doesNotMatch(
    dump,
    /fixture 8937|private8937@example.com|sensitive_private_record/,
  );
  const columns = env.sql
    .prepare("PRAGMA table_info(submissions)")
    .all()
    .map((r) => r.name);
  for (const field of PRIVATE_FIELDS)
    assert.ok(!columns.includes(field), field);
  assert.match(row.message, /Private fixture 8937/);
  assert.ok(row.payload_id);
});
test("missing, altered, and wrong-submission payload objects fail closed", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await submitted(env),
    row = await metadata(env, receipt.id),
    key = payloadKey(row.id, row.payload_id),
    original = env.RAW.data.get(key);
  await env.RAW.put(key, new TextEncoder().encode("altered"));
  await assert.rejects(submission(env, row.id));
  const wrong = JSON.parse(new TextDecoder().decode(original));
  wrong.submissionID = crypto.randomUUID();
  const data = new TextEncoder().encode(JSON.stringify(wrong));
  await env.RAW.put(key, data);
  await query(
    env,
    "UPDATE payload_generations SET bytes=?,sha256=? WHERE id=?",
    data.length,
    await digest(data),
    row.payload_id,
  ).run();
  await assert.rejects(submission(env, row.id), { code: "payload_invalid" });
  await env.RAW.delete(key);
  await assert.rejects(submission(env, row.id));
  assert.equal(env.notices.length, 0);
});
test("every payload generation and file prefix expires even after all SQL rows disappear", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await submitted(env);
  let row = await submission(env, receipt.id);
  await commitPayload(env, row, { review_text: "Private review generation." });
  row = await submission(env, row.id);
  await commitPayload(env, row, {
    draft_json: '{"title":"Another generation"}',
  });
  const saved = snapshot(env),
    marker = await markerByID(env, row.id);
  await env.RAW.put(
    `${row.id}/${crypto.randomUUID()}/attempt`,
    new Uint8Array([1]),
  );
  await env.REBUILT.put(
    `${row.id}/${crypto.randomUUID()}/capture.jpg`,
    new Uint8Array([2]),
  );
  for (const { name } of [...saved].reverse())
    env.sql.exec(`DELETE FROM ${name}`);
  t.mock.method(Date, "now", () => (marker.createdAt + 31 * 86400) * 1000);
  assert.equal(await purgeExpired(env), 1);
  assert.equal(env.RAW.data.size, 0);
  assert.equal(env.REBUILT.data.size, 0);
  restore(env, saved);
  await assert.rejects(submission(env, row.id), {
    code: "retention_unavailable",
  });
  const retry = await api(
    request("/v1/reservations", "POST", receipt.body),
    env,
  );
  assert.equal(retry.status, 410);
  assert.equal(await markerByID(env, row.id), null);
  assert.equal(env.RAW.data.size, 0);
});
test("missing authority never initializes or recreates content from a restored reservation", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await submitted(env);
  await env.RAW.delete(`retention/${receipt.id}.json`);
  await query(
    env,
    "UPDATE submissions SET payload_id=NULL WHERE id=?",
    receipt.id,
  ).run();
  const retry = await api(
    request("/v1/reservations", "POST", receipt.body),
    env,
  );
  assert.equal(retry.status, 503);
  assert.equal(await markerByID(env, receipt.id), null);
  assert.equal(
    (
      await api(
        request(
          `/v1/submissions/${receipt.id}`,
          "GET",
          undefined,
          receipt.token,
        ),
        env,
      )
    ).status,
    503,
  );
});
test("pointer publication uses compare-and-swap and tracks losing generations before storage", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await submitted(env),
    row = await submission(env, receipt.id);
  const original = env.RAW.put;
  let tracked = false;
  env.RAW.put = async (key, data, opts) => {
    if (key.startsWith("payloads/")) {
      const id = key.split("/").at(-1).slice(0, -5);
      tracked = !!(await query(
        env,
        "SELECT id FROM payload_generations WHERE id=?",
        id,
      ).first());
    }
    return original(key, data, opts);
  };
  const first = await commitPayload(env, row, {
    review_text: "Winning private generation.",
  });
  assert.ok(first);
  assert.equal(tracked, true);
  assert.equal(
    await commitPayload(env, row, {
      review_text: "Losing private generation.",
    }),
    null,
  );
  assert.equal(
    (await submission(env, row.id)).review_text,
    "Winning private generation.",
  );
  assert.equal(
    (
      await query(
        env,
        "SELECT id FROM payload_generations WHERE submission_id=?",
        row.id,
      ).all()
    ).results.length,
    3,
  );
  const marker = await markerByID(env, row.id);
  t.mock.method(Date, "now", () => (marker.createdAt + 31 * 86400) * 1000);
  await purgeExpired(env);
  assert.equal(env.RAW.data.size, 0);
});
test("a restored ninety-day SQL pointer cannot extend a later held retention marker", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env);
  await processSubmission(env, receipt.id, async () => passed());
  let row = await submission(env, receipt.id);
  assert.equal((await markerByID(env, row.id)).phase, "screened");
  const screenedSnapshot = snapshot(env);
  assert.ok(
    await commitPayload(
      env,
      row,
      { reason_codes: '["private_record"]' },
      {
        metadata: { status: "held", expires_at: row.created_at + 30 * 86400 },
        expected: { status: "screened" },
        beforeCommit: () => markHeld(env, row, row._retention),
      },
    ),
  );
  const heldMarker = await markerByID(env, row.id);
  restore(env, screenedSnapshot);
  await assert.rejects(submission(env, row.id), {
    code: "publication_unconfirmed",
  });
  await notifyScreened(env, await metadata(env, row.id));
  assert.equal(env.notices.length, 1);
  t.mock.method(Date, "now", () => (heldMarker.createdAt + 31 * 86400) * 1000);
  assert.equal(await purgeExpired(env), 1);
  assert.equal(env.RAW.data.size, 0);
  assert.equal(await metadata(env, row.id), null);
});
test("database rollback can shorten but never exceed R2 authority", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env);
  const original = await metadata(env, receipt.id);
  await processSubmission(env, receipt.id, async () => passed());
  await query(
    env,
    "UPDATE submissions SET expires_at=? WHERE id=?",
    original.expires_at,
    receipt.id,
  ).run();
  const row = await submission(env, receipt.id);
  assert.equal(row.expires_at, original.expires_at);
  t.mock.method(Date, "now", () => (original.created_at + 31 * 86400) * 1000);
  await assert.rejects(submission(env, row.id), { code: "submission_expired" });
  await purgeExpired(env);
  assert.equal(env.RAW.data.size, 0);
});
test("a replaced marker prevents a stale scan from promoting retention or delivering content", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env),
    original = env.RAW.put;
  let raced = false;
  env.RAW.put = async (key, data, opts) => {
    const marker = typeof data === "string" ? JSON.parse(data) : null;
    if (
      !raced &&
      key === `retention/${receipt.id}.json` &&
      marker?.phase === "screened"
    ) {
      raced = true;
      const current = await markerByID(env, receipt.id);
      await original(
        key,
        JSON.stringify({
          ...current,
          etag: undefined,
          revision: crypto.randomUUID(),
        }),
        { onlyIf: { etagMatches: current.etag } },
      );
    }
    return original(key, data, opts);
  };
  await processSubmission(env, receipt.id, async () => passed());
  assert.equal(raced, true);
  assert.equal((await markerByID(env, receipt.id)).phase, "held");
  assert.equal(env.notices.length, 0);
  await assert.rejects(submission(env, receipt.id), {
    code: "publication_unconfirmed",
  });
  await query(
    env,
    "UPDATE submissions SET scan_lease_until=? WHERE id=?",
    nowSeconds() - 1,
    receipt.id,
  ).run();
  await maintenance(env);
  assert.equal((await submission(env, receipt.id)).status, "held");
  assert.equal(
    (await markerByID(env, receipt.id)).expiresAt,
    (await metadata(env, receipt.id)).created_at + 30 * 86400,
  );
});
test("an uncertain marker write confirms only its exact completed revision", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env),
    original = env.RAW.put;
  let interrupted = false;
  env.RAW.put = async (key, data, opts) => {
    const result = await original(key, data, opts);
    if (
      !interrupted &&
      key === `retention/${receipt.id}.json` &&
      typeof data === "string" &&
      JSON.parse(data).phase === "screened"
    ) {
      interrupted = true;
      throw new Error("uncertain write");
    }
    return result;
  };
  await processSubmission(env, receipt.id, async () => passed());
  assert.equal(interrupted, true);
  assert.equal((await submission(env, receipt.id)).status, "screened");
  assert.equal(env.notices.length, 1);
});
test("a crash before marker promotion remains private and maintenance never infers approval from SQL", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env);
  let row = await submission(env, receipt.id);
  const claim = crypto.randomUUID();
  await query(
    env,
    "UPDATE submissions SET status='scanning',scan_claim=?,scan_lease_until=? WHERE id=?",
    claim,
    nowSeconds() + 180,
    row.id,
  ).run();
  row = await submission(env, row.id);
  await commitPayload(
    env,
    row,
    { screened_text: "Unconfirmed screened fixture." },
    {
      metadata: { status: "screened", expires_at: row.created_at + 90 * 86400 },
      expected: { status: "scanning", scan_claim: claim },
      lease: true,
    },
  );
  await assert.rejects(submission(env, row.id), {
    code: "publication_unconfirmed",
  });
  await notifyScreened(env, await metadata(env, row.id));
  assert.equal(env.notices.length, 0);
  await query(
    env,
    "UPDATE submissions SET scan_lease_until=? WHERE id=?",
    nowSeconds() - 1,
    row.id,
  ).run();
  await maintenance(env);
  const held = await submission(env, row.id);
  assert.equal(held.status, "held");
  assert.equal((await markerByID(env, row.id)).phase, "held");
  assert.equal(
    env.notices.some((n) => n.text.includes("Unconfirmed screened fixture")),
    false,
  );
});
test("interrupted final publication requires recheck even when a marker already exists", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env);
  await processSubmission(env, receipt.id, async () => passed());
  const row = await submission(env, receipt.id),
    marker = await markerByID(env, row.id);
  await query(
    env,
    "UPDATE submissions SET scan_lease_until=? WHERE id=?",
    nowSeconds() - 1,
    row.id,
  ).run();
  await maintenance(env);
  assert.equal((await submission(env, row.id)).status, "held");
  assert.notEqual((await markerByID(env, row.id)).revision, marker.revision);
  assert.equal((await markerByID(env, row.id)).phase, "held");
  assert.equal((await metadata(env, row.id)).scan_lease_until, null);
});
test("expiration claims an R2 tombstone before deletion and stale promotion cannot resurrect it", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await submitted(env),
    row = await submission(env, receipt.id),
    old = await markerByID(env, row.id);
  await query(
    env,
    "UPDATE submissions SET expires_at=? WHERE id=?",
    nowSeconds() - 1,
    row.id,
  ).run();
  const original = env.RAW.delete;
  let blocked = false;
  env.RAW.delete = async (keys) => {
    if (
      !blocked &&
      Array.isArray(keys) &&
      keys.some((k) => k.startsWith(`payloads/${row.id}/`))
    ) {
      blocked = true;
      await assert.rejects(markHeld(env, row, old), {
        code: "retention_conflict",
      });
      assert.equal((await markerByID(env, row.id)).phase, "expired");
    }
    return original(keys);
  };
  await purgeRetention(env);
  assert.equal(blocked, true);
  assert.equal(await markerByID(env, row.id), null);
  assert.equal(env.RAW.data.size, 0);
});
test("late writes without a marker are swept independently of database metadata", async (t) => {
  const env = environment();
  t.after(env.close);
  const id = crypto.randomUUID();
  await env.RAW.put(`${id}/${crypto.randomUUID()}/late`, new Uint8Array([1]));
  await env.RAW.put(
    `payloads/${id}/${crypto.randomUUID()}.json`,
    "private orphan",
  );
  await env.REBUILT.put(
    `${id}/${crypto.randomUUID()}/late.jpg`,
    new Uint8Array([2]),
  );
  await sweepOrphans(env, env.RAW, "raw");
  await sweepOrphans(env, env.REBUILT, "rebuilt");
  assert.equal(env.RAW.data.size, 0);
  assert.equal(env.REBUILT.data.size, 0);
});
test("private-payload migration accepts only an empty original database and removes content columns", () => {
  const schema = readFileSync(
      new URL("../schema.sql", import.meta.url),
      "utf8",
    ),
    old = schema
      .replace(
        "payload_id TEXT,",
        "message TEXT NOT NULL,contact_email TEXT NOT NULL DEFAULT '',reason_codes TEXT NOT NULL DEFAULT '[]',screened_text TEXT,review_text TEXT,draft_json TEXT,approval_json TEXT,",
      )
      .replace(
        /CREATE TABLE IF NOT EXISTS payload_generations \([\s\S]*?\);\n/,
        "",
      );
  const migration = readFileSync(
    new URL("../migrations/0003_private_payloads.sql", import.meta.url),
    "utf8",
  );
  for (const nonempty of [false, true]) {
    const sql = new DatabaseSync(":memory:");
    try {
      sql.exec(old);
      if (nonempty)
        sql
          .prepare(
            "INSERT INTO submissions(id,source,category,identity_hash,idempotency_key,fingerprint,token_hash,message,created_at,reservation_expires_at,expires_at) VALUES('id','native','bug','hash','key','hash','hash','private',1,2,3)",
          )
          .run();
      if (nonempty) {
        assert.throws(() => sql.exec(migration), /CHECK constraint/);
        assert.equal(
          sql.prepare("SELECT message FROM submissions").get().message,
          "private",
        );
      } else {
        sql.exec(migration);
        const columns = sql
          .prepare("PRAGMA table_info(submissions)")
          .all()
          .map((r) => r.name);
        for (const field of PRIVATE_FIELDS)
          assert.ok(!columns.includes(field), field);
        assert.ok(columns.includes("payload_id"));
      }
    } finally {
      sql.close();
    }
  }
});
test("screened material remains available after thirty days and every copy expires at ninety days", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env);
  await processSubmission(env, receipt.id, async () => passed());
  const row = await submission(env, receipt.id),
    marker = await markerByID(env, row.id);
  assert.equal(marker.expiresAt, row.created_at + 90 * 86400);
  let clock = (row.created_at + 31 * 86400) * 1000;
  t.mock.method(Date, "now", () => clock);
  assert.equal((await submission(env, row.id)).status, "screened");
  assert.equal(await purgeExpired(env), 0);
  clock = (row.created_at + 91 * 86400) * 1000;
  await assert.rejects(submission(env, row.id), { code: "submission_expired" });
  assert.equal(await purgeExpired(env), 1);
  assert.equal(env.RAW.data.size, 0);
  assert.equal(env.REBUILT.data.size, 0);
  assert.equal(await metadata(env, row.id), null);
});
test("interrupted initial payload writes retry the same reservation and leave no immortal generation", async (t) => {
  for (const afterWrite of [false, true]) {
    const env = environment();
    t.after(env.close);
    const body = {
      source: "native",
      category: "question",
      message: "Interrupted private body.",
      idempotencyKey: crypto.randomUUID(),
      files: [],
    };
    const original = env.RAW.put;
    let interrupted = false;
    env.RAW.put = async (key, data, opts) => {
      if (!interrupted && key.startsWith("payloads/")) {
        interrupted = true;
        if (afterWrite) await original(key, data, opts);
        throw new Error("storage interruption");
      }
      return original(key, data, opts);
    };
    assert.equal(
      (await api(request("/v1/reservations", "POST", body), env)).status,
      503,
    );
    const raw = await query(env, "SELECT * FROM submissions").first();
    assert.equal(raw.payload_id, null);
    assert.equal(
      (await query(env, "SELECT * FROM payload_generations").all()).results
        .length,
      1,
    );
    env.RAW.put = original;
    const retry = await api(request("/v1/reservations", "POST", body), env);
    assert.equal(retry.status, 200);
    assert.equal((await retry.json()).id, raw.id);
    assert.equal((await submission(env, raw.id)).message, body.message);
    assert.equal(
      (await query(env, "SELECT id FROM submissions").all()).results.length,
      1,
    );
    await query(
      env,
      "UPDATE submissions SET expires_at=? WHERE id=?",
      nowSeconds() - 1,
      raw.id,
    ).run();
    await purgeExpired(env);
    assert.equal(env.RAW.data.size, 0);
  }
});
test("missing screened payload prevents notification and receipt success while queue bodies contain only IDs", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env);
  assert.deepEqual(env.JOBS.sent, [{ id: receipt.id }]);
  await processSubmission(env, receipt.id, async () => passed());
  const row = await submission(env, receipt.id);
  env.notices.length = 0;
  await query(
    env,
    "UPDATE submissions SET notified=0 WHERE id=?",
    row.id,
  ).run();
  await env.RAW.delete(payloadKey(row.id, row.payload_id));
  await notifyScreened(env, await metadata(env, row.id));
  assert.equal(env.notices.length, 0);
  assert.equal((await metadata(env, row.id)).notified, 0);
  const status = await api(
    request(`/v1/submissions/${row.id}`, "GET", undefined, receipt.token),
    env,
  );
  assert.equal(status.status, 503);
  assert.deepEqual(await status.json(), { error: "payload_unavailable" });
});
test("payload commit evaluates expiry and scan lease again after its marker write", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env),
    claim = crypto.randomUUID(),
    clock = Date.now();
  await query(
    env,
    "UPDATE submissions SET status='scanning',scan_claim=?,scan_lease_until=? WHERE id=?",
    claim,
    nowSeconds() + 10,
    receipt.id,
  ).run();
  const row = await submission(env, receipt.id);
  let shifted = clock;
  t.mock.method(Date, "now", () => shifted);
  const changed = await commitPayload(
    env,
    row,
    { review_text: "Cannot publish after lease expiry." },
    {
      metadata: { status: "held" },
      expected: { status: "scanning", scan_claim: claim },
      lease: true,
      beforeCommit: async () => {
        shifted = clock + 20000;
      },
    },
  );
  assert.equal(changed, null);
  assert.equal((await metadata(env, row.id)).status, "scanning");
});
test("a marker promotion that finishes after its scanner lease expires cannot publish", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env),
    clock = Date.now(),
    original = env.RAW.put;
  let shifted = clock;
  t.mock.method(Date, "now", () => shifted);
  env.RAW.put = async (key, data, opts) => {
    const result = await original(key, data, opts);
    if (
      key === `retention/${receipt.id}.json` &&
      typeof data === "string" &&
      JSON.parse(data).phase === "screened"
    )
      shifted = clock + 240000;
    return result;
  };
  await processSubmission(env, receipt.id, async () => passed());
  assert.equal(env.notices.length, 0);
  assert.equal((await markerByID(env, receipt.id)).phase, "held");
  await assert.rejects(submission(env, receipt.id), {
    code: "publication_unconfirmed",
  });
});
test("unavailable marker rollback cannot expose a timed-out publication", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env),
    clock = Date.now(),
    original = env.RAW.put;
  let shifted = clock,
    promoted = false;
  t.mock.method(Date, "now", () => shifted);
  env.RAW.put = async (key, data, opts) => {
    if (key === `retention/${receipt.id}.json` && typeof data === "string") {
      const marker = JSON.parse(data);
      if (promoted && marker.phase === "held")
        throw new Error("R2 unavailable");
      const result = await original(key, data, opts);
      if (marker.phase === "screened") {
        promoted = true;
        shifted = clock + 240000;
      }
      return result;
    }
    return original(key, data, opts);
  };
  await processSubmission(env, receipt.id, async () => passed());
  assert.equal((await markerByID(env, receipt.id)).phase, "screened");
  await assert.rejects(submission(env, receipt.id), {
    code: "publication_unconfirmed",
  });
  assert.equal(env.notices.length, 0);
  env.RAW.put = original;
  await maintenance(env);
  assert.equal((await submission(env, receipt.id)).status, "held");
  assert.equal((await markerByID(env, receipt.id)).phase, "held");
});
test("owner evidence expiry remains an atomic condition after payload storage", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await submitted(env),
    clock = Date.now();
  await query(
    env,
    "UPDATE submissions SET status='held',review_expires_at=? WHERE id=?",
    nowSeconds() + 10,
    receipt.id,
  ).run();
  const row = await submission(env, receipt.id),
    original = env.RAW.put;
  let shifted = clock;
  t.mock.method(Date, "now", () => shifted);
  env.RAW.put = async (key, data, opts) => {
    const result = await original(key, data, opts);
    if (key.startsWith("payloads/")) shifted = clock + 20000;
    return result;
  };
  const updated = await commitPayload(
    env,
    row,
    { approval_json: '{"actor":"expired evidence"}' },
    {
      metadata: { status: "received" },
      expected: { status: "held", review_expires_at: row.review_expires_at },
    },
  );
  assert.equal(updated, null);
  assert.equal((await submission(env, row.id)).approval_json, null);
});
test("D1 engine proof cannot retain arbitrary scanner metadata strings", async (t) => {
  const env = environment();
  t.after(env.close);
  const receipt = await completed(env);
  await processSubmission(env, receipt.id, async () => {
    const result = passed();
    result.scan.engine = "ClamAV private fixture metadata";
    result.scan.extra = "private fixture document";
    return result;
  });
  assert.equal((await submission(env, receipt.id)).status, "screened");
  assert.doesNotMatch(
    JSON.stringify(snapshot(env)),
    /private fixture metadata|private fixture document/,
  );
  assert.equal(
    JSON.parse((await metadata(env, receipt.id)).scan_metadata).engine,
    "ClamAV",
  );
});
