import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import {
  verifyScannerIsolation,
  ISOLATION_SCRIPT,
} from "../src/scanner-diagnostic.js";
import { SCANNER_IMAGE_PREFIX } from "../src/scanner-runtime.js";
import { digest } from "../src/policy.js";
const flags = [
  "INTAKE_ENABLED",
  "NATIVE_ENABLED",
  "PROCESSING_ENABLED",
  "AI_SCREENING_ENABLED",
  "EMAIL_ENABLED",
  "NOTIFICATIONS_ENABLED",
];
const checks = {
  tcpBlocked: true,
  httpsBlocked: true,
  signatureMatched: true,
  credentialsAbsent: true,
};
const image = SCANNER_IMAGE_PREFIX + "a".repeat(64);
async function fixture({ result = checks, exitCode = 0 } = {}) {
  const bytes = new TextEncoder().encode("signature fixture"),
    hash = await digest(bytes);
  const manifest = {
    version: 1,
    updatedAt: new Date().toISOString(),
    files: ["main.cvd", "daily.cvd", "bytecode.cvd"].map((name, n) => ({
      name,
      sha256: hash,
      bytes: bytes.length + n,
    })),
  };
  const env = {
    ...Object.fromEntries(flags.map((f) => [f, "false"])),
    SIGNATURES: {
      async get(key) {
        assert.equal(key, "manifest.json");
        const data = new TextEncoder().encode(JSON.stringify(manifest));
        return { size: data.length, arrayBuffer: async () => data.buffer };
      },
    },
  };
  const state = { calls: [], killed: 0 };
  const ctx = {
    id: { toString: () => "single-scanner-id" },
    exports: { ContainerProxy: (props) => props },
    container: {
      running: true,
      images: { scanner: image },
      async inspect() {
        return { image };
      },
      async interceptOutboundHttp() {},
      async exec(cmd, opts) {
        state.calls.push({
          cmd,
          opts,
          stdin: await new Response(opts.stdin).json(),
        });
        return {
          stdout: new Response(
            typeof result === "string" ? result : JSON.stringify(result),
          ).body,
          exitCode: Promise.resolve(exitCode),
          kill() {
            state.killed++;
          },
        };
      },
    },
  };
  const managed = {
    constructor: { name: "Scanner" },
    applyOutboundInterceptionPromise: Promise.resolve(),
    defaultPort: 8080,
    async startAndWaitForPorts() {
      state.ready = true;
    },
    async destroy() {
      throw new Error("unexpected destroy");
    },
  };
  return { managed, ctx, env, state, manifest };
}
test("private diagnostic accepts no arguments and requires every launch flag exactly false", async () => {
  for (const flag of flags)
    for (const value of ["true", false, undefined]) {
      const f = await fixture();
      f.env[flag] = value;
      const result = await verifyScannerIsolation(f.managed, f.ctx, f.env);
      assert.equal(result.error, "diagnostic_disabled");
      assert.equal(f.state.calls.length, 0);
    }
  const f = await fixture();
  assert.equal(
    (await verifyScannerIsolation(f.managed, f.ctx, f.env, 1)).error,
    "diagnostic_arguments_forbidden",
  );
  assert.equal(f.state.calls.length, 0);
});
test("diagnostic uses the scanner lock and only fixed exec arguments with bounded trusted stdin", async () => {
  const f = await fixture();
  f.managed.scanning = true;
  assert.equal(
    (await verifyScannerIsolation(f.managed, f.ctx, f.env)).error,
    "scanner_busy",
  );
  f.managed.scanning = false;
  const result = await verifyScannerIsolation(f.managed, f.ctx, f.env);
  assert.deepEqual(result, { ok: true, ...checks, image, error: null });
  assert.equal(f.managed.scanning, false);
  assert.equal(f.state.ready, true);
  assert.equal(f.state.calls.length, 1);
  assert.deepEqual(f.state.calls[0].cmd, ["python", "-c", ISOLATION_SCRIPT]);
  assert.equal(f.state.calls[0].opts.stderr, "ignore");
  assert.deepEqual(f.state.calls[0].opts.env, {});
  assert.deepEqual(f.state.calls[0].stdin, {
    name: "bytecode.cvd",
    sha256: f.manifest.files[2].sha256,
    bytes: f.manifest.files[2].bytes,
  });
});
test("missing exec, untrusted manifests, malformed output, and nonzero exits fail closed without error excerpts", async () => {
  for (const kind of [
    "exec",
    "manifest",
    "output",
    "extra",
    "oversize",
    "exit",
    "throw",
  ]) {
    const f = await fixture({
      result:
        kind === "output"
          ? "private secret"
          : kind === "extra"
            ? { ...checks, secret: "private secret" }
            : kind === "oversize"
              ? "x".repeat(2049)
              : checks,
      exitCode: kind === "exit" ? 124 : 0,
    });
    if (kind === "exec") delete f.ctx.container.exec;
    if (kind === "manifest") f.manifest.files[0].name = "../../private";
    if (kind === "throw")
      f.ctx.container.exec = async () => {
        throw new Error("private secret");
      };
    const result = await verifyScannerIsolation(f.managed, f.ctx, f.env);
    assert.equal(result.ok, false);
    assert.equal(f.managed.scanning, false);
    assert.doesNotMatch(JSON.stringify(result), /private secret|\.\.\//);
    assert.equal(typeof result.error, "string");
  }
});
test("negative isolation checks cannot report success and no public route reaches the diagnostic", async () => {
  const f = await fixture({ result: { ...checks, httpsBlocked: false } });
  const result = await verifyScannerIsolation(f.managed, f.ctx, f.env);
  assert.equal(result.ok, false);
  assert.equal(result.httpsBlocked, false);
  assert.equal(result.error, "isolation_check_failed");
  const worker = readFileSync(
    new URL("../src/worker.js", import.meta.url),
    "utf8",
  );
  assert.doesNotMatch(worker, /verifyIsolation|diagnostic/);
  const source = readFileSync(
    new URL("../src/container.js", import.meta.url),
    "utf8",
  );
  assert.match(source, /async verifyIsolation\(\)/);
  assert.match(source, /arguments.length/);
});
test("fixed Python probe checks public TCP, HTTPS, exact private signature, and the scanner process environment", () => {
  const harness = `import builtins,hashlib,io,json,os,socket,sys,urllib.error,urllib.request\nfrom unittest.mock import patch\nsource=json.loads(sys.stdin.read())\ndata=b'signature fixture'\nmanifest={'name':'bytecode.cvd','sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}\nclass Opener:\n def open(self,url,timeout):\n  if url=='https://example.com': raise urllib.error.URLError('blocked')\n  assert url=='http://signatures.nextshot.internal/'+manifest['sha256']+'/bytecode.cvd'\n  return io.BytesIO(data)\ndef opened(path,mode):\n assert path=='/proc/1/environ'\n return io.BytesIO(b'PATH=/usr/local/bin\\x00HF_HUB_OFFLINE=1\\x00')\nwith patch('socket.create_connection',side_effect=OSError('blocked')) as tcp,patch('urllib.request.build_opener',return_value=Opener()),patch('builtins.open',side_effect=opened),patch.dict(os.environ,{},clear=True):\n sys.stdin=io.StringIO(json.dumps(manifest))\n exec(source)\n assert tcp.call_args.args[0]==('1.1.1.1',443)\n`;
  const run = spawnSync("python3", ["-c", harness], {
    input: JSON.stringify(ISOLATION_SCRIPT),
    encoding: "utf8",
    timeout: 15000,
  });
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(JSON.parse(run.stdout), checks);
  const sensitive = harness.replace(
    "PATH=/usr/local/bin\\x00HF_HUB_OFFLINE=1\\x00",
    "GITHUB_TOKEN=never-print-this-value\\x00",
  );
  const privateRun = spawnSync("python3", ["-c", sensitive], {
    input: JSON.stringify(ISOLATION_SCRIPT),
    encoding: "utf8",
    timeout: 15000,
  });
  assert.equal(privateRun.status, 0, privateRun.stderr);
  assert.equal(JSON.parse(privateRun.stdout).credentialsAbsent, false);
  assert.doesNotMatch(privateRun.stdout, /never-print-this-value/);
  assert.match(ISOLATION_SCRIPT, /signal.alarm\(12\)/);
});
test("the diagnostic lock covers an active process and its deadline terminates that process", async (t) => {
  const f = await fixture();
  t.mock.timers.enable({ apis: ["setTimeout"] });
  let controller, finish;
  f.ctx.container.exec = async () => {
    f.state.calls.push({});
    return {
      stdout: new ReadableStream({
        start(value) {
          controller = value;
        },
      }),
      exitCode: new Promise((resolve) => {
        finish = resolve;
      }),
      kill() {
        f.state.killed++;
        controller.close();
        finish(137);
      },
    };
  };
  const pending = verifyScannerIsolation(f.managed, f.ctx, f.env);
  while (!f.state.calls.length)
    await new Promise((resolve) => setImmediate(resolve));
  assert.equal(f.managed.scanning, true);
  assert.equal(
    (await verifyScannerIsolation(f.managed, f.ctx, f.env)).error,
    "scanner_busy",
  );
  t.mock.timers.tick(15001);
  const result = await pending;
  assert.equal(result.error, "diagnostic_timeout");
  assert.equal(result.ok, false);
  assert.ok(f.state.killed >= 1);
  assert.equal(f.managed.scanning, false);
});
