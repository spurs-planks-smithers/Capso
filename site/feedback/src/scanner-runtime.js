export const SCANNER_IMAGE_PREFIX =
  "registry.cloudflare.com/2afca1b8aab7ec4024bdb7cb2fec47c0/nextshot-feedback-scanner-scanner@sha256:";
export const SCANNER_IDLE_MS = 150000;
export const SCANNER_STARTUP_MS = 60000;
export const SCANNER_RPC_MS = 200000;
export function startupSignal(signal) {
  return signal
    ? AbortSignal.any([signal, AbortSignal.timeout(SCANNER_STARTUP_MS)])
    : AbortSignal.timeout(SCANNER_STARTUP_MS);
}
export async function abortable(promise, signal) {
  if (!signal) return promise;
  if (signal.aborted) {
    Promise.resolve(promise).catch(() => {});
    signal.throwIfAborted();
  }
  let stop;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        stop = () => reject(signal.reason || new Error("scanner_aborted"));
        signal.addEventListener("abort", stop, { once: true });
      }),
    ]);
  } finally {
    signal.removeEventListener("abort", stop);
  }
}
export async function ensureScannerRuntime(ctx, signal) {
  signal?.throwIfAborted();
  const container = ctx.container,
    image = container?.images?.scanner;
  if (
    typeof image !== "string" ||
    !image.startsWith(SCANNER_IMAGE_PREFIX) ||
    !/^[a-f0-9]{64}$/.test(image.slice(SCANNER_IMAGE_PREFIX.length))
  )
    throw new Error("scanner_image_unavailable");
  if (typeof ctx.exports?.ContainerProxy !== "function")
    throw new Error("scanner_proxy_unavailable");
  const info = await abortable(container.inspect(), signal);
  if (info && info.image !== "" && info.image !== image)
    await abortable(container.destroy(), signal);
  await abortable(
    container.interceptOutboundHttp(
      "signatures.nextshot.internal",
      ctx.exports.ContainerProxy(),
    ),
    signal,
  );
  signal?.throwIfAborted();
  if (!container.running)
    container.start({ image, instance: "standard-2", enableInternet: false });
  await abortable(container.setInactivityTimeout(SCANNER_IDLE_MS), signal);
  return image;
}
export async function readBounded(response, maximum, signal) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error("missing_body");
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const part = await abortable(reader.read(), signal);
      if (part.done) break;
      size += part.value.byteLength;
      if (size > maximum) throw new Error("body_limit");
      chunks.push(part.value);
    }
  } catch (error) {
    reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}
export async function waitForScannerReady(ctx, signal) {
  const bounded = startupSignal(signal),
    port = ctx.container.getTcpPort(8080);
  while (!bounded.aborted) {
    try {
      if (!ctx.container.running) await ensureScannerRuntime(ctx, bounded);
      const attempt = AbortSignal.any([bounded, AbortSignal.timeout(2000)]);
      const response = await abortable(
        port.fetch("http://scanner/ready", {
          method: "GET",
          redirect: "manual",
          signal: attempt,
        }),
        attempt,
      );
      const body = await readBounded(response, 1024, attempt);
      let value;
      try {
        value = JSON.parse(body);
      } catch {}
      if (
        response.status === 200 &&
        value?.ready === true &&
        Object.keys(value).length === 1
      )
        return;
    } catch {
      if (bounded.aborted) break;
    }
    await abortable(
      new Promise((resolve) => setTimeout(resolve, 250)),
      bounded,
    );
  }
  throw new Error("scanner_readiness_timeout");
}
