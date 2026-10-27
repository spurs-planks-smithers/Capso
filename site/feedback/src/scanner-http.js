import {
  ensureScannerRuntime,
  waitForScannerReady,
  startupSignal,
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
export async function scannerFetch(managed, ctx, request) {
  const url = new URL(request.url);
  if (request.method !== "POST" || url.pathname !== "/scan" || url.search)
    return new Response(null, { status: 404 });
  if (managed.scanning) return hold("scanner_busy");
  managed.scanning = true;
  try {
    const input = await uploadBytes(request.body, 36000000),
      signal = startupSignal(request.signal);
    await ensureScannerRuntime(ctx, signal);
    await waitForScannerReady(ctx, signal);
    const response = await ctx.container
      .getTcpPort(8080)
      .fetch("http://scanner/scan", {
        method: "POST",
        redirect: "manual",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": String(input.byteLength),
        },
        body: input,
        signal: AbortSignal.any([request.signal, AbortSignal.timeout(140000)]),
      });
    return response;
  } catch {
    return hold("scanner_unavailable");
  } finally {
    managed.scanning = false;
  }
}
