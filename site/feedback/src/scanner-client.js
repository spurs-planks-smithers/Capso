import { readBounded, SCANNER_RPC_MS } from "./scanner-runtime.js";
const HOLD = (reason) => ({
  version: 1,
  status: "held",
  reasonCodes: [reason],
});
export async function scan(env, job) {
  if (!env.SCANNER || !env.SIGNATURES) return HOLD("scanner_unavailable");
  try {
    const manifest = await env.SIGNATURES.get("manifest.json");
    if (!manifest || manifest.size > 4096)
      return HOLD("signatures_unavailable");
    const signatureManifest = JSON.parse(await manifest.text()),
      input = JSON.stringify({ ...job, signatureManifest }),
      length = new TextEncoder().encode(input).byteLength;
    if (length > 36000000) return HOLD("scanner_input_limit");
    const signal = AbortSignal.timeout(SCANNER_RPC_MS),
      stub = env.SCANNER.getByName("nextshot-single-scanner");
    const response = await stub.fetch("http://scanner/scan", {
      method: "POST",
      redirect: "manual",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": String(length),
      },
      body: input,
      signal,
    });
    if (!response.ok)
      return HOLD(
        response.status === 503 ? "scanner_busy" : "scanner_unavailable",
      );
    const result = JSON.parse(await readBounded(response, 24000000, signal));
    if (
      result.version !== 1 ||
      !["passed", "held", "rejected"].includes(result.status)
    )
      return HOLD("invalid_scanner_result");
    return result;
  } catch {
    return HOLD("scanner_unavailable");
  }
}
