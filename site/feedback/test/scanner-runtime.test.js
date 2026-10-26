import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  ensureScannerRuntime,
  SCANNER_IMAGE_PREFIX,
} from "../src/scanner-runtime.js";
const image = SCANNER_IMAGE_PREFIX + "a".repeat(64);
function runtime({ running = false, info = null, reference = image } = {}) {
  const events = [],
    starts = [],
    intercepts = [];
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
    },
    async interceptOutboundHttp(host, proxy) {
      events.push("intercept");
      intercepts.push({ host, proxy });
    },
  };
  const ctx = {
    container,
    id: { toString: () => "single-scanner-id" },
    exports: {
      ContainerProxy(options) {
        events.push("proxy");
        return options;
      },
    },
  };
  const managed = {
    constructor: { name: "Scanner" },
    applyOutboundInterceptionPromise: Promise.resolve().then(() =>
      events.push("sdk-interception"),
    ),
    async destroy() {
      events.push("destroy");
      container.running = false;
    },
  };
  return { ctx, managed, events, starts, intercepts };
}
test("native scanner starts only the pinned image with explicit standard-2 and internet disabled", async () => {
  const state = runtime();
  await ensureScannerRuntime(state.managed, state.ctx);
  assert.deepEqual(state.starts, [
    { image, instance: "standard-2", enableInternet: false },
  ]);
  assert.deepEqual(state.intercepts, [
    {
      host: "signatures.nextshot.internal",
      proxy: {
        props: {
          enableInternet: false,
          containerId: "single-scanner-id",
          className: "Scanner",
        },
      },
    },
  ]);
  assert.ok(
    state.events.indexOf("sdk-interception") <
      state.events.indexOf("intercept"),
  );
  assert.ok(state.events.indexOf("intercept") < state.events.indexOf("start"));
});
test("an already running scanner is not started twice", async () => {
  const state = runtime({ running: true, info: { image } });
  await ensureScannerRuntime(state.managed, state.ctx);
  await ensureScannerRuntime(state.managed, state.ctx);
  assert.equal(state.starts.length, 0);
  assert.equal(state.events.includes("destroy"), false);
});
test("a nonempty stale image is destroyed before the configured image starts", async () => {
  const state = runtime({
    running: true,
    info: { image: SCANNER_IMAGE_PREFIX + "b".repeat(64) },
  });
  await ensureScannerRuntime(state.managed, state.ctx);
  assert.equal(state.starts.length, 1);
  assert.ok(
    state.events.indexOf("destroy") < state.events.indexOf("intercept"),
  );
  assert.ok(state.events.indexOf("intercept") < state.events.indexOf("start"));
});
test("an empty starting image does not restart a running scanner", async () => {
  const state = runtime({ running: true, info: { image: "" } });
  await ensureScannerRuntime(state.managed, state.ctx);
  assert.equal(state.starts.length, 0);
  assert.equal(state.events.includes("destroy"), false);
});
test("missing, unpinned, and foreign runtime images fail before inspection or startup", async () => {
  for (const reference of [
    undefined,
    "",
    image.replace(/@sha256:.*/, ":latest"),
    image.replace("registry.cloudflare.com", "docker.io"),
    image.replace("2afca1b8aab7ec4024bdb7cb2fec47c0", "f".repeat(32)),
    image.replace("nextshot-feedback-scanner-scanner", "unrelated"),
    image + "\n",
    image.replace("a".repeat(64), "A".repeat(64)),
  ]) {
    const state = runtime({ reference });
    if (reference === undefined) delete state.ctx.container.images.scanner;
    await assert.rejects(
      ensureScannerRuntime(state.managed, state.ctx),
      /scanner_image_unavailable/,
    );
    assert.equal(state.starts.length, 0);
    assert.equal(state.events.includes("inspect"), false);
    assert.equal(state.intercepts.length, 0);
  }
});
test("an unavailable SDK interceptor or proxy prevents startup", async () => {
  for (const mode of ["sdk", "proxy", "interceptor"]) {
    const state = runtime();
    if (mode === "sdk")
      state.managed.applyOutboundInterceptionPromise = Promise.reject(
        new Error("sdk unavailable"),
      );
    if (mode === "proxy") delete state.ctx.exports.ContainerProxy;
    if (mode === "interceptor")
      state.ctx.container.interceptOutboundHttp = async () => {
        throw new Error("interception unavailable");
      };
    await assert.rejects(ensureScannerRuntime(state.managed, state.ctx));
    assert.equal(state.starts.length, 0);
  }
});
test("the checked-in configuration uses durable scheduling and one named scanner queue", () => {
  const config = JSON.parse(
    readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8"),
  );
  assert.equal(config.containers.length, 1);
  assert.deepEqual(config.containers[0], {
    class_name: "Scanner",
    scheduling_policy: "durable_object",
    images: { scanner: { dockerfile: "./scanner/Dockerfile" } },
  });
  assert.equal(config.queues.consumers.length, 1);
  assert.equal(config.queues.consumers[0].max_concurrency, 1);
  assert.equal(config.queues.consumers[0].max_batch_size, 1);
  assert.ok(
    SCANNER_IMAGE_PREFIX.includes(
      `/${config.account_id}/${config.name}-scanner-scanner@sha256:`,
    ),
  );
  const source = readFileSync(
    new URL("../src/container.js", import.meta.url),
    "utf8",
  );
  assert.equal(
    (source.match(/getByName\('nextshot-single-scanner'\)/g) || []).length,
    1,
  );
  assert.match(source, /await ensureScannerRuntime\(this, this.ctx\)/);
  assert.match(
    source,
    /await this.startAndWaitForPorts\(this.defaultPort, \{ abort: request.signal \}\)/,
  );
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

test("the outbound proxy uses the actual bundled scanner class name", async () => {
  const state = runtime();
  state.managed.constructor = { name: "BundledScanner" };
  await ensureScannerRuntime(state.managed, state.ctx);
  assert.equal(state.intercepts[0].proxy.props.className, "BundledScanner");
});
