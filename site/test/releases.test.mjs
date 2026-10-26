// Run with: node --test site/test/releases.test.mjs
import assert from "node:assert/strict";
import { test } from "node:test";
import { contentType, parseLatest, releaseKey, unsatisfiableRange } from "../src/releases.mjs";

const hash = "a".repeat(64);
const good = { version: "0.4.0", build: 631, file: "Nextshot-0.4.0.dmg", size: 13000000, sha256: hash };

test("releaseKey allows published names and nothing else", () => {
  assert.equal(releaseKey("Nextshot-0.4.0.dmg"), "releases/Nextshot-0.4.0.dmg");
  assert.equal(releaseKey("Nextshot-0.4.0.zip"), "releases/Nextshot-0.4.0.zip");
  assert.equal(releaseKey("Nextshot-0.4.0.dmg.sha256"), "releases/Nextshot-0.4.0.dmg.sha256");
  assert.equal(releaseKey("Nextshot-0.4.0.json"), "releases/Nextshot-0.4.0.json");
  assert.equal(releaseKey("Nextshot-12.30.45.dmg"), "releases/Nextshot-12.30.45.dmg");
  assert.equal(releaseKey("Nextshot-2026.10.24-9d3afc7.dmg"), "releases/Nextshot-2026.10.24-9d3afc7.dmg");
});

test("releaseKey refuses a path, a traversal, and an odd name", () => {
  for (const name of [
    "../latest.json",
    "latest.json",
    "legacy/Nextshot-0.4.0.dmg",
    "Nextshot-0.4.0.dmg/../x",
    "Nextshot-0.4.dmg",
    "Nextshot-0.4.0-dirty.dmg",
    "Nextshot-0.4.0-rc.1.dmg",
    "Nextshot-0.4.0.exe",
    "nextshot-0.4.0.dmg",
    "Nextshot-0.4.0.dmg\n",
    "",
    undefined,
    null,
  ]) {
    assert.equal(releaseKey(name), null, `should refuse ${JSON.stringify(name)}`);
  }
});

test("contentType follows the extension", () => {
  assert.equal(contentType("Nextshot-0.4.0.dmg"), "application/x-apple-diskimage");
  assert.equal(contentType("Nextshot-0.4.0.zip"), "application/zip");
  assert.equal(contentType("Nextshot-0.4.0.json"), "application/json");
  assert.equal(contentType("Nextshot-0.4.0.dmg.sha256"), "text/plain; charset=utf-8");
});

test("unsatisfiableRange is true only for bytes that do not exist", () => {
  assert.equal(unsatisfiableRange("bytes=100-200", 100), true);
  assert.equal(unsatisfiableRange("bytes=100-", 100), true);
  assert.equal(unsatisfiableRange("bytes=500-600", 100), true);
  assert.equal(unsatisfiableRange("bytes=-0", 100), true);
  assert.equal(unsatisfiableRange("bytes=99-200", 100), false);
  assert.equal(unsatisfiableRange("bytes=0-0", 100), false);
  assert.equal(unsatisfiableRange("bytes=-5", 100), false);
  assert.equal(unsatisfiableRange("bytes=-", 100), false);
  assert.equal(unsatisfiableRange("bytes=0-1,5-6", 100), false);
  assert.equal(unsatisfiableRange("items=100-200", 100), false);
  assert.equal(unsatisfiableRange(null, 100), false);
  assert.equal(unsatisfiableRange("", 100), false);
});

test("parseLatest reads a good record", () => {
  const record = parseLatest(JSON.stringify({ ...good, commit: "abc1234", released: "2026-10-26T00:00:00Z", notes: "Fixed it." }));
  assert.deepEqual(record, { ...good, commit: "abc1234", released: "2026-10-26T00:00:00Z", notes: "Fixed it." });
});

test("parseLatest accepts a date build, which also has three integers", () => {
  const legacy = { ...good, version: "2026.10.24", build: 524, file: "Nextshot-2026.10.24-9d3afc7.dmg" };
  assert.equal(parseLatest(JSON.stringify(legacy))?.version, "2026.10.24");
});

test("parseLatest fills the optional fields", () => {
  const record = parseLatest(JSON.stringify(good));
  assert.equal(record.commit, null);
  assert.equal(record.released, null);
  assert.equal(record.notes, "");
});

test("parseLatest refuses text that is not a record", () => {
  assert.equal(parseLatest("{not json"), null);
  assert.equal(parseLatest("null"), null);
  assert.equal(parseLatest("[]"), null);
  assert.equal(parseLatest('"text"'), null);
  assert.equal(parseLatest(""), null);
});

test("parseLatest refuses a record with a missing or wrong field", () => {
  const bad = [
    { ...good, version: "0.4" },
    { ...good, version: "0.4.0-rc.1" },
    { ...good, version: 4 },
    { ...good, build: 0 },
    { ...good, build: "631" },
    { ...good, file: "../latest.json" },
    { ...good, file: "Nextshot-0.4.0.zip" },
    { ...good, file: "Nextshot-0.4.0.json" },
    { ...good, size: 0 },
    { ...good, size: "13" },
    { ...good, sha256: "abc" },
    { ...good, sha256: "A".repeat(64) },
  ];
  for (const record of bad) {
    assert.equal(parseLatest(JSON.stringify(record)), null, `should refuse ${JSON.stringify(record)}`);
  }
  for (const key of Object.keys(good)) {
    const { [key]: _removed, ...rest } = good;
    assert.equal(parseLatest(JSON.stringify(rest)), null, `should refuse a record without ${key}`);
  }
});
