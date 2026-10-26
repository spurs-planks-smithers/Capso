import { environment, rawFileCount } from "./fixture.js";
import { submission } from "../src/store.js";
import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { inbound } from "../src/email.js";
const env = environment;
function mail(body, to = "hi@nextshot.dev") {
  const data = new TextEncoder().encode(body);
  return {
    to,
    from: "sender@example.com",
    rawSize: data.length,
    raw: new Response(data).body,
    rejected: null,
    setReject(reason) {
      this.rejected = reason;
    },
    forward() {
      throw new Error("Original forwarding is forbidden");
    },
  };
}
test("plain inbound email is privately queued without trusting submitted auth headers", async (t) => {
  const e = env();
  t.after(() => e.sql.close());
  const m = mail(
    "From: sender@example.com\r\nTo: hi@nextshot.dev\r\nAuthentication-Results: fake; spf=pass\r\nSubject: Save button\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nSave stays disabled.",
  );
  await inbound(m, e);
  const row = await submission(
    e,
    e.sql.prepare("SELECT id FROM submissions").get().id,
  );
  assert.equal(row.status, "received");
  assert.match(row.message, /Save stays disabled/);
  assert.doesNotMatch(row.message, /spf=pass/);
  assert.equal(rawFileCount(e), 1);
  assert.equal(e.JOBS.sent.length, 1);
  assert.equal(
    e.sql.prepare("SELECT role FROM files").get().role,
    "email-original",
  );
});
test("unsupported inline attachments hold the entire email and never forward it", async (t) => {
  const e = env();
  t.after(() => e.sql.close());
  const m = mail(
    'From: sender@example.com\r\nSubject: Report\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\nContent-Type: text/plain\r\n\r\nA report.\r\n--x\r\nContent-Type: application/pdf\r\nContent-Disposition: inline; filename="report.pdf"\r\nContent-Transfer-Encoding: base64\r\n\r\nJVBERi0=\r\n--x--',
  );
  await inbound(m, e);
  const row = await submission(
    e,
    e.sql.prepare("SELECT id FROM submissions").get().id,
  );
  assert.equal(row.status, "held");
  assert.equal(row.message, "");
  assert.match(row.reason_codes, /email_attachment_type/);
  assert.equal(e.JOBS.sent.length, 0);
  assert.equal(rawFileCount(e), 1);
});
test("exact address and email enable gate reject mail without reading or forwarding it", async (t) => {
  const e = env();
  t.after(() => e.sql.close());
  const wrong = mail("body", "other@nextshot.dev");
  await inbound(wrong, e);
  assert.ok(wrong.rejected);
  e.EMAIL_ENABLED = "false";
  const disabled = mail("body");
  await inbound(disabled, e);
  assert.ok(disabled.rejected);
  assert.equal(e.RAW.data.size, 0);
});
