import { Container, ContainerProxy } from '@cloudflare/containers';
export { ContainerProxy };

const MAX_JOB = 36_000_000;
const MAX_REPLY = 24_000_000;
const HOLD = reason => ({ version: 1, status: 'held', reasonCodes: [reason] });

export class Scanner extends Container {
  defaultPort = 8080;
  sleepAfter = '150s';
  enableInternet = false;
  pingEndpoint = 'localhost/ready';

  async fetch(request) {
    // One named instance plus this in-memory lease rejects overlapping jobs.
    if (this.scanning) return new Response(JSON.stringify(HOLD('scanner_busy')), { status: 503 });
    this.scanning = true;
    try { return await this.containerFetch(request); }
    finally { this.scanning = false; }
  }
}

Scanner.outboundByHost = {
  'signatures.nextshot.internal': async (request, env) => {
    const url = new URL(request.url);
    const match = /^\/([a-f0-9]{64})\/(main\.cvd|daily\.cvd|bytecode\.cvd)$/.exec(url.pathname);
    if (request.method !== 'GET' || url.search || !match || !env.SIGNATURES) return new Response(null, { status: 403 });
    const object = await env.SIGNATURES.get(`definitions/${match[1]}/${match[2]}`);
    if (!object || object.size > 300_000_000) return new Response(null, { status: 404 });
    return new Response(object.body, { headers: { 'Content-Length': String(object.size), 'Content-Type': 'application/octet-stream' } });
  },
};

async function readBounded(response, maximum) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error('missing_body');
  const chunks = []; let bytes = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      bytes += part.value.byteLength;
      if (bytes > maximum) throw new Error('body_limit');
      chunks.push(part.value);
    }
  } catch (error) { await reader.cancel(); throw error; }
  const output = new Uint8Array(bytes); let offset = 0;
  for (const chunk of chunks) { output.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder('utf-8', { fatal: true }).decode(output);
}

export async function scan(env, job) {
  if (!env.SCANNER || !env.SIGNATURES) return HOLD('scanner_unavailable');
  try {
    const manifest = await env.SIGNATURES.get('manifest.json');
    if (!manifest || manifest.size > 4096) return HOLD('signatures_unavailable');
    const signatureManifest = JSON.parse(await manifest.text());
    const input = JSON.stringify({ ...job, signatureManifest });
    if (new TextEncoder().encode(input).byteLength > MAX_JOB) return HOLD('scanner_input_limit');
    const stub = env.SCANNER.getByName('nextshot-single-scanner');
    const response = await stub.fetch('http://scanner/scan', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: input,
      signal: AbortSignal.timeout(125_000),
    });
    if (!response.ok) return HOLD(response.status === 503 ? 'scanner_busy' : 'scanner_unavailable');
    const result = JSON.parse(await readBounded(response, MAX_REPLY));
    if (result.version !== 1 || !['passed','held','rejected'].includes(result.status)) return HOLD('invalid_scanner_result');
    return result;
  } catch { return HOLD('scanner_unavailable'); }
}
