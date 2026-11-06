// Run with: node --test site/test/staged-site.test.mjs
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { checkSearchFile } from "../src/staged-site.mjs";

// A small assets folder like the one stage() builds. No npm and no build run here.
// It holds another Pagefind file, so only pagefind.js itself is under test.
function folder() {
  const assets = mkdtempSync(join(tmpdir(), "nextshot-search-file-"));
  const put = (path, text) => {
    mkdirSync(join(assets, path, ".."), { recursive: true });
    writeFileSync(join(assets, path), text);
  };
  put("guides/index.html", "guide home");
  put("guides/pagefind/pagefind-ui.js", "other search file");
  return { assets, put, clean: () => rmSync(assets, { recursive: true, force: true }) };
}

test("checkSearchFile accepts a pagefind.js that has content", () => {
  const f = folder();
  try {
    f.put("guides/pagefind/pagefind.js", "search runtime");
    assert.doesNotThrow(() => checkSearchFile(f.assets));
  } finally { f.clean(); }
});

test("checkSearchFile refuses a missing pagefind.js", () => {
  const f = folder();
  try {
    assert.throws(() => checkSearchFile(f.assets), /Guides search file is missing: guides\/pagefind\/pagefind\.js/);
    rmSync(join(f.assets, "guides/pagefind"), { recursive: true });
    assert.throws(() => checkSearchFile(f.assets), /Guides search file is missing: guides\/pagefind\/pagefind\.js/);
  } finally { f.clean(); }
});

test("checkSearchFile refuses a 0-byte pagefind.js", () => {
  const f = folder();
  try {
    f.put("guides/pagefind/pagefind.js", "");
    assert.throws(() => checkSearchFile(f.assets), /Guides search file is empty \(0 bytes\): guides\/pagefind\/pagefind\.js/);
  } finally { f.clean(); }
});

test("checkSearchFile refuses a folder named pagefind.js", () => {
  const f = folder();
  try {
    f.put("guides/pagefind/pagefind.js/inside.txt", "a folder has a size too");
    assert.throws(() => checkSearchFile(f.assets), /Guides search file is missing: guides\/pagefind\/pagefind\.js/);
  } finally { f.clean(); }
});
