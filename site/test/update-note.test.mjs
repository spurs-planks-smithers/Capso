// node --test site/test/update-note.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const read = (name) => readFileSync(new URL(`../${name}`, import.meta.url), "utf8");
const script = read("public/update-note.js");
const page = read("public/index.html");
const worker = read("src/worker.js");

// The script runs with no document, so it publishes its functions and stops.
function load() {
  const context = {};
  vm.createContext(context);
  vm.runInContext(script, context);
  const api = context.nextshotUpdateNote;
  assert.ok(api && typeof api.describe === "function", "the script published no describe function");
  return api;
}

// A result from another realm: copy it so deepEqual compares plain objects.
const plain = (value) => JSON.parse(JSON.stringify(value));

test("the script file is not empty", () => {
  assert.ok(script.length > 500, `update-note.js holds only ${script.length} characters`);
});

test("a page without #from= stays as it was", () => {
  const { describe } = load();
  for (const hash of ["", "#", "#top", "#from", "#From=0.5.0", "from=0.5.0", " #from=0.5.0", undefined, null, 5]) {
    assert.equal(describe(hash, "0.5.1"), null, `hash ${JSON.stringify(hash)}`);
  }
});

test("the same version says the visitor has the newest build", () => {
  const { describe } = load();
  assert.deepEqual(plain(describe("#from=0.5.1", "0.5.1")), { comparison: "You have the newest build." });
});

test("an older version names both versions", () => {
  const { describe } = load();
  assert.deepEqual(plain(describe("#from=0.4.9", "0.5.1")), { comparison: "You have 0.4.9. Version 0.5.1 is out." });
  assert.deepEqual(plain(describe("#from=0.5.0", "0.10.0")), { comparison: "You have 0.5.0. Version 0.10.0 is out." });
});

test("versions compare as numbers, not as text", () => {
  const { describe } = load();
  assert.equal(plain(describe("#from=0.9.0", "0.10.0")).comparison, "You have 0.9.0. Version 0.10.0 is out.");
  assert.equal(plain(describe("#from=0.10.0", "0.9.0")).comparison, null);
  assert.equal(plain(describe("#from=1.0.0", "0.99.99")).comparison, null);
});

test("a newer version, or one that cannot be compared, shows no comparison line", () => {
  const { describe } = load();
  const cases = [
    ["#from=0.6.0", "0.5.0"],
    ["#from=0.5.0-dev", "0.5.1"],
    ["#from=", "0.5.1"],
    ["#from=01.2.3", "0.5.1"],
    ["#from=1.2.3.4", "0.5.1"],
    ["#from=0.5.0%20", "0.5.1"],
    ["#from=0.5.0&x=1", "0.5.1"],
    ["#from=99999999999.0.0", "0.5.1"],
    ["#from=0.5.0", "{{VERSION}}"],
    ["#from=0.5.0", "undefined"],
    ["#from=0.5.0", ""],
    ["#from=0.5.0", undefined],
  ];
  for (const [hash, current] of cases) {
    const result = plain(describe(hash, current));
    assert.deepEqual(result, { comparison: null }, `${hash} against ${current}`);
  }
});

test("hostile text in the hash never reaches the result", () => {
  const { describe } = load();
  for (const hash of [
    "#from=<script>alert(1)</script>",
    "#from=<img src=x onerror=alert(1)>",
    "#from=0.5.0\"><b>x</b>",
    "#from=javascript:alert(1)",
    "#from=%3Cscript%3E",
  ]) {
    const result = JSON.stringify(describe(hash, "0.5.1"));
    assert.equal(result, '{"comparison":null}', hash);
  }
});

// The note must send nothing and write no markup. Comments may name these words.
const forbidden = [
  [/\bfetch\b/, "fetch"],
  [/XMLHttpRequest/, "XMLHttpRequest"],
  [/sendBeacon/, "sendBeacon"],
  [/\bnew\s+Image\b|\bImage\s*\(/, "Image"],
  [/WebSocket|EventSource/, "WebSocket or EventSource"],
  [/importScripts|\bimport\s*\(/, "dynamic import"],
  [/innerHTML|outerHTML|insertAdjacentHTML|document\.write/, "HTML writing"],
  [/\beval\b|new\s+Function/, "eval"],
  [/\.src\s*=|setAttribute\(\s*["'](?:src|href)/, "src or href assignment"],
  [/navigator\./, "navigator"],
  [/window\.open|location\.(?:href|assign|replace)\s*=/, "navigation"],
];

function violations(source) {
  const code = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");
  return forbidden.filter(([pattern]) => pattern.test(code)).map(([, name]) => name);
}

test("the script makes no request and writes no HTML", () => {
  assert.deepEqual(violations(script), []);
});

test("the scan catches what it guards", () => {
  assert.deepEqual(violations('fetch("/x")'), ["fetch"]);
  assert.deepEqual(violations("new XMLHttpRequest()"), ["XMLHttpRequest"]);
  assert.deepEqual(violations("navigator.sendBeacon('/p')"), ["sendBeacon", "navigator"]);
  assert.deepEqual(violations('new Image().src = "/p"'), ["Image", "src or href assignment"]);
  assert.deepEqual(violations("el.innerHTML = x"), ["HTML writing"]);
  assert.deepEqual(violations("// fetch is only named in a comment\nconst a = 1;"), []);
});

test("the page holds the note, hidden, and loads the script", () => {
  assert.match(page, /<aside class="update-note" id="update-note" data-version="\{\{VERSION\}\}" hidden>/);
  assert.match(page, /<p class="update-compare" hidden><\/p>/);
  assert.match(page, /<script src="\/update-note\.js" defer><\/script>/);
  // The Worker fills {{VERSION}} in every place it appears.
  assert.match(worker, /replaceAll\("\{\{VERSION\}\}"/);
});

test("the note says what Drew asked it to say", () => {
  const note = page.match(/<p class="update-offline">([\s\S]*?)<\/p>/);
  assert.ok(note, "the page has no offline paragraph");
  const text = note[1].replace(/<[^>]+>/g, "");
  assert.equal(
    text,
    "Nextshot stays offline, so it cannot update itself or send us anything. " +
      "Download the newest DMG, open it, and double-click Nextshot on the image to update. " +
      "Tell us what you think at feedback.nextshot.dev.",
  );
  assert.match(note[1], /<a href="https:\/\/feedback\.nextshot\.dev\/">feedback\.nextshot\.dev<\/a>/);
});
