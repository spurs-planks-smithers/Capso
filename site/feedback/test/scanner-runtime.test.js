import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  ensureScannerRuntime,
  waitForScannerReady,
  SCANNER_IMAGE_PREFIX,
  SCANNER_IDLE_MS,
  SCANNER_STARTUP_MS,
} from "../src/scanner-runtime.js";
import { scannerFetch, signatureProxy } from "../src/scanner-http.js";
import { scan } from "../src/scanner-client.js";
const image = SCANNER_IMAGE_PREFIX + "a".repeat(64);
function runtime({ running = false, info = null, reference = image } = {}) {
  const events = [],
    starts = [],
    intercepts = [],
    requests = [],
    proxy = {};
  const container = {
    images: { scanner: reference },
    running,
    async inspect() {
      events.push("inspect");
      return info;
    },
    start(options) {
      events.push("start");
      starts.push(options);
      this.running = true;
      info = { image: options.image };
    },
    async destroy() {
      events.push("destroy");
      this.running = false;
      info = null;
    },
    async interceptOutboundHttp(host, handler) {
      events.push("intercept");
      intercepts.push({ host, handler });
    },
    async setInactivityTimeout(ms) {
      events.push("idle");
      assert.equal(ms, 150000);
    },
    getTcpPort(port) {
      assert.equal(port, 8080);
      return {
        async fetch(url, options) {
          requests.push({ url, options });
          return new Response(JSON.stringify({ ready: true }));
        },
      };
    },
  };
  const ctx = {
    container,
    id: { toString: () => "single-scanner-id" },
    exports: {
      ContainerProxy(...args) {
        assert.equal(args.length, 0);
        return proxy;
      },
    },
  };
  return { ctx, events, starts, intercepts, requests, proxy };
}
test("native scanner pins its image, resources, denied internet, fixed proxy, and idle deadline", async () => {
  const s = runtime();
  await ensureScannerRuntime(s.ctx);
  assert.deepEqual(s.starts, [
    { image, instance: "standard-2", enableInternet: false },
  ]);
  assert.deepEqual(s.intercepts, [
    { host: "signatures.nextshot.internal", handler: s.proxy },
  ]);
  assert.ok(s.events.indexOf("intercept") < s.events.indexOf("start"));
  assert.equal(s.events.at(-1), "idle");
  assert.equal(SCANNER_IDLE_MS, 150000);
  assert.equal(SCANNER_STARTUP_MS, 60000);
});
test("native running scanner avoids double start and replaces a stale nonempty digest", async () => {
  const current = runtime({ running: true, info: { image } });
  await ensureScannerRuntime(current.ctx);
  await ensureScannerRuntime(current.ctx);
  assert.equal(current.starts.length, 0);
  assert.equal(current.events.includes("destroy"), false);
  const stale = runtime({
    running: true,
    info: { image: SCANNER_IMAGE_PREFIX + "b".repeat(64) },
  });
  await ensureScannerRuntime(stale.ctx);
  assert.equal(stale.starts.length, 1);
  assert.ok(stale.events.indexOf("destroy") < stale.events.indexOf("start"));
  const starting = runtime({ running: true, info: { image: "" } });
  await ensureScannerRuntime(starting.ctx);
  assert.equal(starting.starts.length, 0);
});
test("native startup rejects missing, unpinned, and foreign images before any provider call", async () => {
  for (const reference of [
    "",
    image.replace(/@sha256:.*/, ":latest"),
    image.replace("registry.cloudflare.com", "docker.io"),
    image.replace("2afca1b8aab7ec4024bdb7cb2fec47c0", "f".repeat(32)),
    image.replace("nextshot-feedback-scanner-scanner", "foreign"),
    image + "\n",
  ]) {
    const s = runtime({ reference });
    await assert.rejects(
      ensureScannerRuntime(s.ctx),
      /scanner_image_unavailable/,
    );
    assert.equal(s.events.length, 0);
  }
});
test("native readiness requires port8080 status200 and exact ready true", async () => {
  const s = runtime({ running: true, info: { image } });
  await waitForScannerReady(s.ctx);
  assert.equal(s.requests[0].url, "http://scanner/ready");
  assert.equal(s.requests[0].options.redirect, "manual");
  for (const response of [
    new Response('{"ready":false}'),
    new Response('{"ready":true}', { status: 503 }),
    new Response("x".repeat(1025)),
  ]) {
    const controller = new AbortController();
    s.ctx.container.getTcpPort = () => ({
      fetch: async () => {
        queueMicrotask(() => controller.abort());
        return response;
      },
    });
    await assert.rejects(waitForScannerReady(s.ctx, controller.signal));
  }
});
test("native readiness has a sixty-second deadline even when provider fetch never resolves", async (t) => {
  const s = runtime({ running: true, info: { image } }),
    controller = new AbortController(),
    original = AbortSignal.timeout;
  let deadline;
  t.mock.method(AbortSignal, "timeout", (ms) => {
    if (ms === 60000) {
      deadline = ms;
      return controller.signal;
    }
    return original(ms);
  });
  s.ctx.container.getTcpPort = () => ({ fetch: () => new Promise(() => {}) });
  const pending = waitForScannerReady(s.ctx);
  controller.abort();
  await assert.rejects(pending);
  assert.equal(deadline, 60000);
});
test("private scanner fetch permits only POST scan, keeps the job lock, and forwards measured UTF8 bytes", async () => {
  const s = runtime({ running: true, info: { image } }),
    managed = { scanning: false };
  for (const [method, path] of [
    ["GET", "/scan"],
    ["POST", "/ready"],
    ["POST", "/scan?x=1"],
  ]) {
    const result = await scannerFetch(
      managed,
      s.ctx,
      new Request("http://scanner" + path, { method }),
    );
    assert.equal(result.status, 404);
  }
  assert.equal(s.events.length, 0);
  managed.scanning = true;
  assert.equal(
    (
      await scannerFetch(
        managed,
        s.ctx,
        new Request("http://scanner/scan", { method: "POST", body: "{}" }),
      )
    ).status,
    503,
  );
  managed.scanning = false;
  const payload = '{"message":"café"}';
  s.ctx.container.getTcpPort = () => ({
    async fetch(url, options) {
      if (url.endsWith("/ready")) return new Response('{"ready":true}');
      assert.equal(url, "http://scanner/scan");
      assert.equal(options.method, "POST");
      assert.equal(options.redirect, "manual");
      assert.equal(
        options.headers["Content-Length"],
        String(new TextEncoder().encode(payload).length),
      );
      assert.deepEqual(options.body, new TextEncoder().encode(payload));
      return new Response(
        '{"version":1,"status":"held","reasonCodes":["test"]}',
      );
    },
  });
  assert.equal(
    (
      await scannerFetch(
        managed,
        s.ctx,
        new Request("http://scanner/scan", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: payload,
        }),
      )
    ).status,
    200,
  );
  assert.equal(managed.scanning, false);
});
test("fixed signature proxy exposes only immutable private definitions and never fetches arbitrary URLs", async () => {
  const keys = [],
    env = {
      SIGNATURES: {
        async get(key) {
          keys.push(key);
          return { size: 3, body: new Uint8Array([1, 2, 3]) };
        },
      },
    };
  const good = `http://signatures.nextshot.internal/${"a".repeat(64)}/bytecode.cvd`;
  assert.equal((await signatureProxy(new Request(good), env)).status, 200);
  assert.deepEqual(keys, [`definitions/${"a".repeat(64)}/bytecode.cvd`]);
  for (const url of [
    good + "?x=1",
    good.replace("signatures.nextshot.internal", "example.com"),
    good.replace("bytecode.cvd", "upload.zip"),
    good.replace("http:", "https:"),
  ])
    assert.equal((await signatureProxy(new Request(url), env)).status, 403);
  assert.equal(
    (await signatureProxy(new Request(good, { method: "POST" }), env)).status,
    403,
  );
  assert.equal(keys.length, 1);
});
test("scan client uses the singleton, exact UTF8 content length, and a two-hundred-second RPC deadline", async (t) => {
  let timeout, forwarded;
  const original = AbortSignal.timeout;
  t.mock.method(AbortSignal, "timeout", (ms) => {
    timeout = ms;
    return original(ms);
  });
  const env = {
    SIGNATURES: { get: async () => ({ size: 2, text: async () => "{}" }) },
    SCANNER: {
      getByName(name) {
        assert.equal(name, "nextshot-single-scanner");
        return {
          async fetch(url, options) {
            forwarded = { url, options };
            return new Response(
              '{"version":1,"status":"held","reasonCodes":["test"]}',
            );
          },
        };
      },
    },
  };
  await scan(env, { submission: { message: "café" } });
  assert.equal(timeout, 200000);
  assert.equal(forwarded.options.redirect, "manual");
  assert.equal(
    forwarded.options.headers["Content-Length"],
    String(new TextEncoder().encode(forwarded.options.body).length),
  );
});
test("configuration and scanner source retain durable singleton isolation without the SDK", () => {
  const config = JSON.parse(
    readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8"),
  );
  assert.equal(config.containers.length, 1);
  assert.deepEqual(config.containers[0], {
    class_name: "Scanner",
    scheduling_policy: "durable_object",
    images: { scanner: { dockerfile: "./scanner/Dockerfile" } },
  });
  assert.equal(config.queues.consumers[0].max_concurrency, 1);
  const source = readFileSync(
    new URL("../src/container.js", import.meta.url),
    "utf8",
  );
  assert.match(source, /Scanner extends DurableObject/);
  assert.match(source, /ContainerProxy extends WorkerEntrypoint/);
  assert.doesNotMatch(
    source,
    /@cloudflare\/containers|outboundByHost|startAndWaitForPorts|containerFetch/,
  );
  const pkg = JSON.parse(
    readFileSync(new URL("../package.json", import.meta.url), "utf8"),
  );
  assert.equal(pkg.dependencies["@cloudflare/containers"], undefined);
  for (const flag of [
    "INTAKE_ENABLED",
    "NATIVE_ENABLED",
    "PROCESSING_ENABLED",
    "AI_SCREENING_ENABLED",
    "EMAIL_ENABLED",
    "NOTIFICATIONS_ENABLED",
  ])
    assert.equal(config.vars[flag], "false");
});
test("native runtime reports fixed inspect, destroy, intercept, start, and inactivity failure codes", async () => {
  for (const step of [
    "inspect",
    "destroy",
    "intercept",
    "start",
    "inactivity",
  ]) {
    const s = runtime({
        running: step === "destroy",
        info:
          step === "destroy"
            ? { image: SCANNER_IMAGE_PREFIX + "b".repeat(64) }
            : null,
      }),
      error = new Error("private provider message");
    const key = {
      inspect: "inspect",
      destroy: "destroy",
      intercept: "interceptOutboundHttp",
      start: "start",
      inactivity: "setInactivityTimeout",
    }[step];
    s.ctx.container[key] = () => {
      throw error;
    };
    await assert.rejects(ensureScannerRuntime(s.ctx), (failure) => {
      assert.equal(failure.code, `scanner_runtime_${step}_failed`);
      assert.equal(failure.message, failure.code);
      return true;
    });
  }
  const badImage = runtime({ reference: "untrusted" });
  await assert.rejects(ensureScannerRuntime(badImage.ctx), {
    code: "scanner_image_unavailable",
  });
  const badProxy = runtime();
  delete badProxy.ctx.exports.ContainerProxy;
  await assert.rejects(ensureScannerRuntime(badProxy.ctx), {
    code: "scanner_proxy_unavailable",
  });
});
