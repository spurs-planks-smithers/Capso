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


// The same deploy path runs against fixture commands. Nothing reaches Cloudflare.
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, cpSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { verify, deploymentSnapshot, snapshotVersion } from "../src/staged-site.mjs";

const source = resolve(import.meta.dirname, "../..");
const deployment = { id: "11111111-1111-1111-1111-111111111111", created_on: "2026-10-26T00:00:00Z", versions: [{ version_id: "22222222-2222-2222-2222-222222222222", percentage: 100 }] };
function fixture() {
  const root = mkdtempSync(join(tmpdir(), "nextshot-publishing-"));
  const put = (path, text, executable = false) => {
    mkdirSync(join(root, path, ".."), { recursive: true });
    writeFileSync(join(root, path), text, executable ? { mode: 0o755 } : {});
  };
  put("site/public/index.html", '<video src="/media/{{VIDEO}}" poster="/media/{{POSTER}}"></video>{{VERSION}}');
  put("site/public/nested/kept.txt", "recursive public file");
  put("site/guides/dist/index.html", "guide home");
  put("site/guides/dist/pagefind/pagefind.js", "search runtime");
  put("site/guides/dist/clips/capture.mp4", "guide clip bytes");
  put("site/guides/package.json", "{}");
  put(".github/assets/nextshot-icon.png", "icon");
  put("scripts/video/nextshot-onboarding/assets/fonts/Inter-latin.woff2", "font");
  put("LICENSE", "license"); put("VERSION", "0.4.0");
  put("video.mp4", "homepage video"); put("poster.jpg", "approved poster");
  for (const path of ["site/src/staged-site.mjs", "site/src/worker.js", "site/src/releases.mjs", "site/wrangler.jsonc", "site/deploy.sh", "site/worker-deployment.sh"]) {
    mkdirSync(join(root, path, ".."), { recursive: true }); cpSync(join(source, path), join(root, path));
  }
  put("bin/npm", '#!/bin/bash\necho npm >>"$FIXTURE_ROOT/calls"\nexit "${NPM_FAIL:-0}"\n', true);
  put("bin/git", '#!/bin/bash\necho abc1234567890\n', true);
  const activated = { ...deployment, id: "33333333-3333-3333-3333-333333333333", created_on: "2026-10-26T00:01:00Z", versions: [{ version_id: "44444444-4444-4444-4444-444444444444", percentage: 100 }] };
  put("bin/wrangler", `#!/bin/bash
printf 'wrangler %s\\n' "$*" >>"$FIXTURE_ROOT/calls"
case "$1 $2" in
  "deployments list")
    if [[ -f "$FIXTURE_ROOT/activated" ]]; then echo '${JSON.stringify([activated])}'; else echo '${JSON.stringify([deployment])}'; fi ;;
  "deploy --config")
    if [[ "\${DEPLOY_FAIL:-0}" == 0 || "\${DEPLOY_ACTIVATES_ON_FAILURE:-0}" == 1 ]]; then touch "$FIXTURE_ROOT/activated"; fi
    exit "\${DEPLOY_FAIL:-0}" ;;
  "rollback "*)
    [[ "\${ROLLBACK_FAIL:-0}" == 0 ]] || exit 1
    [[ "\${ROLLBACK_NO_EFFECT:-0}" == 1 ]] || rm -f "$FIXTURE_ROOT/activated"
    exit "\${ROLLBACK_ERROR_AFTER_RESTORE:-0}" ;;
esac
`, true);
  put("scripts/release-lib.sh", `r2_login() { :; }
r2_get() { printf '{"version":"0.4.0"}' >"$2"; }
record_valid() { return 0; }
`, true);
  put("site/smoke.sh", `#!/bin/bash
printf 'smoke %s\\n' "$*" >>"$FIXTURE_ROOT/calls"
case " $* " in *' --guides '*) exit "\${GUIDE_SMOKE_FAIL:-0}" ;; esac
exit 0
`, true);
  const env = { ...process.env, PATH: `${root}/bin:${process.env.PATH}`, FIXTURE_ROOT: root };
  return { root, env, put, clean: () => rmSync(root, { recursive: true, force: true }) };
}
function staged(f) {
  // stage() runs the actual npm commands. PATH selects fixture commands only.
  const result = spawnSync(process.execPath, [join(f.root, "site/src/staged-site.mjs"), "stage", f.root, join(f.root, "video.mp4"), join(f.root, "poster.jpg")], { env: f.env, encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim().split("\n").at(-1);
}

test("complete site artifact freezes config, Worker imports, nested public files, media, and Range sizes", () => {
  const f = fixture();
  try {
    const artifact = staged(f);
    const metadata = verify(artifact);
    assert.equal(readFileSync(join(artifact, "assets/nested/kept.txt"), "utf8"), "recursive public file");
    assert.equal(readFileSync(join(artifact, "assets/media/video-poster.jpg"), "utf8"), "approved poster");
    assert.match(metadata.sizes, /\/guides\/clips\/capture\.mp4=16/);
    assert.match(metadata.sizes, /\/media\/video\.mp4=14/);
    const config = JSON.parse(readFileSync(join(artifact, "wrangler.json")));
    assert.equal(config.assets.directory, "./assets");
    assert.equal(config.vars.SIZES, metadata.sizes);
    assert.equal(config.assets.not_found_handling, "404-page");
    assert.ok(metadata.files["src/releases.mjs"]);
    const another = staged(f);
    assert.notEqual(artifact, another);
    writeFileSync(join(artifact, "assets/nested/kept.txt"), "changed after approval");
    assert.throws(() => verify(artifact), /checksum changed/);
    writeFileSync(join(another, "unexpected.txt"), "extra bytes");
    assert.throws(() => verify(another), /inventory changed/);
  } finally { f.clean(); }
});

test("Worker snapshot chooses the newest complete deployment and refuses empty or split deployments", () => {
  assert.equal(deploymentSnapshot([{ ...deployment, created_on: "2026-10-25T00:00:00Z", id: "33333333-3333-3333-3333-333333333333" }, deployment]).deploymentId, deployment.id);
  assert.throws(() => deploymentSnapshot([]), /No Worker deployments/);
  assert.throws(() => snapshotVersion({ versionId: "bad" }), /Invalid Worker rollback snapshot/);
  assert.throws(() => deploymentSnapshot([{ ...deployment, versions: [{ ...deployment.versions[0], percentage: 50 }] }]), /stable version/);
});

test("deploy-staged publishes the sealed artifact with stdin closed and never runs npm again", () => {
  const f = fixture();
  try {
    const artifact = staged(f);
    f.put("site/public/index.html", "later unrelated edit");
    f.put("poster.jpg", "changed poster");
    const result = spawnSync("bash", [join(f.root, "site/deploy.sh"), "--deploy-staged", artifact], { env: { ...f.env, NPM_FAIL: "9" }, input: "", encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    const calls = readFileSync(join(f.root, "calls"), "utf8");
    assert.equal((calls.match(/^npm$/gm) || []).length, 2);
    assert.ok(calls.indexOf("smoke --url") < calls.indexOf("wrangler deployments list"));
    assert.ok(calls.indexOf("wrangler deployments list") < calls.indexOf("wrangler deploy --config"));
    assert.match(calls, /--config .*site-.*\/wrangler.json --env-file \/dev\/null/);
    assert.doesNotMatch(calls, /rollback/);
  } finally { f.clean(); }
});

test("failed Guides smoke restores the recorded Worker version and keeps the exact artifact for site-only retry", () => {
  const f = fixture();
  try {
    const artifact = staged(f);
    const result = spawnSync("bash", [join(f.root, "site/deploy.sh"), "--deploy-staged", artifact], { env: { ...f.env, GUIDE_SMOKE_FAIL: "1" }, input: "", encoding: "utf8" });
    assert.equal(result.status, 1);
    const calls = readFileSync(join(f.root, "calls"), "utf8");
    assert.match(calls, /wrangler rollback 22222222-2222-2222-2222-222222222222/);
    assert.match(result.stderr, /app release files and R2 latest.json stay unchanged/);
    assert.match(result.stderr, /Retry site only: site\/deploy.sh --deploy-staged/);
    assert.doesNotMatch(result.stderr, /--promote/);
    assert.equal(verify(artifact).version, "0.4.0");
    assert.equal(JSON.parse(readFileSync(`${artifact}.rollback.json`)).deploymentId, deployment.id);
  } finally { f.clean(); }
});

test("failed Worker deploy keeps the app live and tampered artifact never reaches delivery", () => {
  const f = fixture();
  try {
    const artifact = staged(f);
    let result = spawnSync("bash", [join(f.root, "site/deploy.sh"), "--deploy-staged", artifact], { env: { ...f.env, DEPLOY_FAIL: "1" }, input: "", encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /app release stays live/);
    const before = readFileSync(join(f.root, "calls"), "utf8");
    writeFileSync(join(artifact, "src/worker.js"), "tampered");
    result = spawnSync("bash", [join(f.root, "site/deploy.sh"), "--deploy-staged", artifact], { env: f.env, input: "", encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.equal(readFileSync(join(f.root, "calls"), "utf8"), before);
  } finally { f.clean(); }
});


test("stage-only reports the exact reusable artifact and fails closed if the Guides build fails", () => {
  const f = fixture();
  try {
    const args = [join(f.root, "site/deploy.sh"), "--stage-only", "--video", join(f.root, "video.mp4"), "--poster", join(f.root, "poster.jpg")];
    let result = spawnSync("bash", args, { env: f.env, input: "", encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(verify(result.stdout.trim().split("\n").at(-1)).guides, true);
    result = spawnSync("bash", args, { env: { ...f.env, NPM_FAIL: "1" }, input: "", encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /nothing was deployed/);
    assert.doesNotMatch(readFileSync(join(f.root, "calls"), "utf8"), /wrangler/);
  } finally { f.clean(); }
});


function releaseFixture() {
  const f = fixture();
  for (const path of ["scripts/release.sh", "scripts/release-lib.sh", "scripts/release-changelog.py"]) {
    cpSync(join(source, path), join(f.root, path));
  }
  f.put("VERSION", "0.3.0");
  f.put("CHANGELOG.md", "## [Unreleased]\n\n- Add Guides.\n\n## [0.3.0] - 2026-10-25\n\n- Previous release.\n");
  f.put("build/releases/Nextshot-onboarding-2026.10.24.mp4", "pinned video");
  f.put("build/site-poster.jpg", "pinned poster");
  for (const name of ["swift", "xcodegen", "xcodebuild", "xcrun", "github-route"]) f.put(`bin/${name}`, "#!/bin/bash\nexit 0\n", true);
  f.put("bin/security", '#!/bin/bash\necho "Developer ID Application"\n', true);
  f.put("bin/git", `#!/bin/bash
printf 'git %s\\n' "$*" >>"$FIXTURE_ROOT/calls"
[[ "$1" != -C ]] || shift 2
case "$1" in
  branch) echo main ;;
  fetch|status|add|tag|push) exit 0 ;;
  rev-parse)
    [[ "$2" != -q ]] || exit 1
    if [[ "$2" == HEAD && -f "$FIXTURE_ROOT/committed" ]]; then echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; else echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; fi ;;
  describe) echo nextshot-v0.3.0 ;;
  log) echo 'feat: Guides' ;;
  rev-list) echo 2 ;;
  commit) touch "$FIXTURE_ROOT/committed" ;;
  reset) rm -f "$FIXTURE_ROOT/committed" ;;
esac
`, true);
  for (const name of ["test-nextshot-version.sh", "test-release.sh"]) f.put(`scripts/${name}`, "#!/bin/bash\nexit 0\n", true);
  f.put("site/test/releases.test.mjs", 'import { test } from "node:test"; test("fixture gate", () => {});');
  f.put("scripts/release-notarized.sh", `#!/bin/bash
v="$(cat "$FIXTURE_ROOT/VERSION")"
mkdir -p "$FIXTURE_ROOT/build/releases"
printf dmg >"$FIXTURE_ROOT/build/releases/Nextshot-$v.dmg"
printf zip >"$FIXTURE_ROOT/build/releases/Nextshot-$v.zip"
`, true);
  const lib = readFileSync(join(f.root, "scripts/release-lib.sh"), "utf8");
  f.put("scripts/release-lib.sh", lib + `
# Fixture boundaries: preserve real release flow and record all delivery calls.
r2_login() { :; }
r2_reachable() { return 0; }
r2_get() {
  [[ "$1" == latest.json ]] || return 1
  printf '{"version":"0.4.0","build":2,"file":"Nextshot-0.4.0.dmg","size":3,"sha256":"${"a".repeat(64)}"}' >"$2"
}
check_dmg() { return 0; }
archive_release() { echo archive >>"$FIXTURE_ROOT/calls"; }
promote_release() { echo promote >>"$FIXTURE_ROOT/calls"; release_previous=0.3.0; }
restore_latest() { echo restore_latest >>"$FIXTURE_ROOT/calls"; }
`);
  f.put("site/smoke.sh", `#!/bin/bash
printf 'smoke %s\\n' "$*" >>"$FIXTURE_ROOT/calls"
case " $* " in *' --guides '*) exit "\${GUIDE_SMOKE_FAIL:-0}" ;; esac
exit "\${APP_SMOKE_FAIL:-0}"
`, true);
  return f;
}
function rehearseRelease(f, overrides = {}, terminal = true) {
  const args = [join(f.root, "scripts/release.sh"), "minor"];
  const env = { ...f.env, ...overrides };
  delete env.NEXTSHOT_R2_LOCAL;
  if (!terminal) return spawnSync("bash", args, { env, input: "", encoding: "utf8" });
  // Only fixture deliveries run. A pseudo-terminal exercises the real approval.
  const driver = `import os,pty,sys
pid,fd=pty.fork()
if pid==0:
 os.execvp('bash',['bash']+sys.argv[1:])
os.write(fd,b'y\\n')
while True:
 try:
  data=os.read(fd,65536)
  if not data: break
  os.write(1,data)
 except OSError: break
_,status=os.waitpid(pid,0)
sys.exit(os.waitstatus_to_exitcode(status))
`;
  return spawnSync("python3", ["-I", "-c", driver, ...args], { env, input: "", encoding: "utf8", timeout: 30000 });
}

test("release approval with closed stdin stops before archive, push, app promotion, or guide delivery", () => {
  const f = releaseFixture();
  try {
    const result = rehearseRelease(f, {}, false);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /no terminal to ask on/);
    assert.doesNotMatch(readFileSync(join(f.root, "calls"), "utf8"), /^archive$|^promote$|git .* push |wrangler deploy --config/m);
  } finally { f.clean(); }
});

test("release keeps the verified app live on guide staging, deploy, or smoke failure, with a site-only retry", () => {
  for (const failure of [{ NPM_FAIL: "1" }, { DEPLOY_FAIL: "1" }, { GUIDE_SMOKE_FAIL: "1" }]) {
    const f = releaseFixture();
    try {
      const result = rehearseRelease(f, failure);
      assert.equal(result.status, 1, result.stdout + result.stderr);
      assert.match(result.stdout, /Released Nextshot 0.4.0/);
      assert.match(result.stdout, /partial success/);
      assert.match(result.stdout, /Retry site only/);
      assert.doesNotMatch(result.stdout, /run: scripts\/release.sh --promote/);
      const calls = readFileSync(join(f.root, "calls"), "utf8");
      assert.match(calls, /^archive$/m);
      assert.match(calls, /^promote$/m);
      assert.doesNotMatch(calls, /restore_latest/);
      if (failure.GUIDE_SMOKE_FAIL) {
        assert.ok(calls.indexOf("smoke --url") < calls.indexOf("wrangler deployments list"));
        assert.match(calls, /wrangler rollback 22222222-2222-2222-2222-222222222222/);
      }
    } finally { f.clean(); }
  }
});

test("app smoke failure restores latest.json and never deploys Guides", () => {
  const f = releaseFixture();
  try {
    const result = rehearseRelease(f, { APP_SMOKE_FAIL: "1" });
    assert.equal(result.status, 1, result.stdout + result.stderr);
    const calls = readFileSync(join(f.root, "calls"), "utf8");
    assert.match(calls, /restore_latest/);
    assert.doesNotMatch(calls, /wrangler deployments list|wrangler deploy --config/);
  } finally { f.clean(); }
});


test("deploy error after activation restores and verifies the saved Worker version without rebuilding", () => {
  const f = fixture();
  try {
    const artifact = staged(f);
    const result = spawnSync("bash", [join(f.root, "site/deploy.sh"), "--deploy-staged", artifact], { env: { ...f.env, DEPLOY_FAIL: "1", DEPLOY_ACTIVATES_ON_FAILURE: "1" }, input: "", encoding: "utf8" });
    assert.equal(result.status, 1);
    const calls = readFileSync(join(f.root, "calls"), "utf8");
    assert.match(calls, /wrangler rollback 22222222-2222-2222-2222-222222222222/);
    assert.equal((calls.match(/wrangler deployments list/g) || []).length, 2);
    assert.equal(existsSync(join(f.root, "activated")), false);
    assert.match(result.stderr, /Worker rollback verified/);
    assert.doesNotMatch(calls, /--guides/);
    assert.equal((calls.match(/^npm$/gm) || []).length, 2);
    assert.equal(verify(artifact).version, "0.4.0");
    assert.match(result.stderr, /Retry site only/);
    assert.doesNotMatch(result.stderr, /--promote/);
  } finally { f.clean(); }
});

test("rollback failure reports unverified Worker state after deploy errors and guide smoke errors", () => {
  for (const failure of [{ DEPLOY_FAIL: "1", DEPLOY_ACTIVATES_ON_FAILURE: "1" }, { GUIDE_SMOKE_FAIL: "1" }]) {
    const f = fixture();
    try {
      const artifact = staged(f);
      const result = spawnSync("bash", [join(f.root, "site/deploy.sh"), "--deploy-staged", artifact], { env: { ...f.env, ...failure, ROLLBACK_FAIL: "1" }, input: "", encoding: "utf8" });
      assert.equal(result.status, 1);
      assert.equal(existsSync(join(f.root, "activated")), true);
      assert.match(result.stderr, /WORKER ROLLBACK FAILED OR UNVERIFIED/);
      assert.match(result.stderr, /new site may still be active/);
      assert.doesNotMatch(result.stderr, /Worker rollback verified|app release stays live/);
      assert.equal(verify(artifact).version, "0.4.0");
    } finally { f.clean(); }
  }
});

test("rollback command success cannot pass when the active Worker version is different", () => {
  const f = fixture();
  try {
    const artifact = staged(f);
    const result = spawnSync("bash", [join(f.root, "site/deploy.sh"), "--deploy-staged", artifact], { env: { ...f.env, GUIDE_SMOKE_FAIL: "1", ROLLBACK_NO_EFFECT: "1" }, input: "", encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /WORKER ROLLBACK FAILED OR UNVERIFIED/);
    assert.doesNotMatch(result.stderr, /Worker rollback verified/);
  } finally { f.clean(); }
});

test("rollback error after recovery uses the observed active version to verify restoration", () => {
  const f = fixture();
  try {
    const artifact = staged(f);
    const result = spawnSync("bash", [join(f.root, "site/deploy.sh"), "--deploy-staged", artifact], { env: { ...f.env, GUIDE_SMOKE_FAIL: "1", ROLLBACK_ERROR_AFTER_RESTORE: "1" }, input: "", encoding: "utf8" });
    assert.equal(result.status, 1);
    assert.equal(existsSync(join(f.root, "activated")), false);
    assert.match(result.stderr, /Worker rollback verified/);
    assert.doesNotMatch(result.stderr, /WORKER ROLLBACK FAILED OR UNVERIFIED/);
  } finally { f.clean(); }
});
