import {
  ensureScannerRuntime,
  waitForScannerReady,
  startupSignal,
  abortable,
  readBounded,
} from "./scanner-runtime.js";
import { uploadBytes } from "./policy.js";
const hold = (reason) =>
  new Response(
    JSON.stringify({ version: 1, status: "held", reasonCodes: [reason] }),
    { status: 503, headers: { "Content-Type": "application/json" } },
  );
export async function signatureProxy(request, env) {
  const url = new URL(request.url),
    match = /^\/([a-f0-9]{64})\/(main\.cvd|daily\.cvd|bytecode\.cvd)$/.exec(
      url.pathname,
    );
  if (
    request.method !== "GET" ||
    url.protocol !== "http:" ||
    url.hostname !== "signatures.nextshot.internal" ||
    url.port ||
    url.search ||
    !match ||
    !env.SIGNATURES
  )
    return new Response(null, { status: 403 });
  const object = await env.SIGNATURES.get(
    `definitions/${match[1]}/${match[2]}`,
  );
  if (!object || object.size > 300000000)
    return new Response(null, { status: 404 });
  return new Response(object.body, {
    headers: {
      "Content-Length": String(object.size),
      "Content-Type": "application/octet-stream",
    },
  });
}
async function destroyForScan(ctx) {
  await abortable(ctx.container.destroy(), AbortSignal.timeout(10000));
}
export async function scannerFetch(managed, ctx, request) {
  const url = new URL(request.url);
  if (request.method !== "POST" || url.pathname !== "/scan" || url.search)
    return new Response(null, { status: 404 });
  if (managed.scanning) return hold("scanner_busy");
  managed.scanning = true;
  let result = hold("scanner_unavailable");
  try {
    const signal = startupSignal(request.signal);
    // A prior process can retain root capabilities. Destroy its VM before any new job.
    await destroyForScan(ctx);
    const input = await uploadBytes(request.body, 36000000);
    await ensureScannerRuntime(ctx, signal);
    await waitForScannerReady(ctx, signal);
    const transfer = AbortSignal.any([
      request.signal,
      AbortSignal.timeout(140000),
    ]);
    const response = await abortable(
      ctx.container.getTcpPort(8080).fetch("http://scanner/scan", {
        method: "POST",
        redirect: "manual",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": String(input.byteLength),
        },
        body: input,
        signal: transfer,
      }),
      transfer,
    );
    const body = await readBounded(response, 24000000, transfer);
    result = new Response(body, {
      status: response.status,
      headers: { "Content-Type": "application/json" },
    });
  } catch {
    result = hold("scanner_unavailable");
  } finally {
    // Cleanup has its own deadline even when the caller's request is already canceled.
    try {
      await destroyForScan(ctx);
    } catch {
      result = hold("scanner_unavailable");
    }
    managed.scanning = false;
  }
  return result;
}
