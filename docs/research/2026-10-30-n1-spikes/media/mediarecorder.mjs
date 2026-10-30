// N1 spike 4: what does the installed Chrome binary record, and does AVFoundation open it?
// Usage: node mediarecorder.mjs <output folder>
// Env: PLAYWRIGHT_CORE (index.mjs of any playwright-core copy), CHROME_PATH (Chrome executable).
// It starts a separate headless instance with a throwaway profile. It touches no user profile.
import fs from 'node:fs';
import path from 'node:path';

const out = process.argv[2];
const { chromium } = await import(process.env.PLAYWRIGHT_CORE);
fs.mkdirSync(out, { recursive: true });
const profile = path.join(out, 'profile');
fs.rmSync(profile, { recursive: true, force: true });
const context = await chromium.launchPersistentContext(profile, { executablePath: process.env.CHROME_PATH, headless: true });
const page = await context.newPage();
await page.goto('about:blank');
const types = ['video/webm', 'video/webm;codecs=vp8', 'video/webm;codecs=vp9', 'video/webm;codecs=h264', 'video/webm;codecs=av1',
  'video/mp4', 'video/mp4;codecs=avc1', 'video/mp4;codecs=avc1.42E01E', 'video/mp4;codecs=hvc1', 'video/x-matroska;codecs=avc1'];
const report = await page.evaluate(async (types) => {
  const supported = Object.fromEntries(types.map((t) => [t, MediaRecorder.isTypeSupported(t)]));
  const canvas = document.createElement('canvas');
  canvas.width = 640; canvas.height = 360;
  const ctx = canvas.getContext('2d');
  const files = {};
  for (const type of types.filter((t) => supported[t])) {
    const stream = canvas.captureStream(15);
    const recorder = new MediaRecorder(stream, { mimeType: type, videoBitsPerSecond: 800000 });
    const chunks = [];
    recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    const done = new Promise((r) => (recorder.onstop = r));
    recorder.start(250);
    const began = performance.now();
    while (performance.now() - began < 2500) {
      ctx.fillStyle = `hsl(${(performance.now() / 8) % 360} 70% 50%)`;
      ctx.fillRect(0, 0, 640, 360);
      ctx.fillStyle = '#fff'; ctx.font = '48px sans-serif';
      ctx.fillText(String(Math.round(performance.now() - began)), 40, 200);
      await new Promise((r) => requestAnimationFrame(r));
    }
    recorder.stop(); await done;
    const blob = new Blob(chunks);
    const bytes = new Uint8Array(await blob.arrayBuffer());
    let binary = ''; for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    files[type] = { size: bytes.length, mime: recorder.mimeType, base64: btoa(binary) };
  }
  return { userAgent: navigator.userAgent, supported, files };
}, types);
const written = [];
for (const [type, file] of Object.entries(report.files)) {
  const ext = file.mime.includes('mp4') ? 'mp4' : file.mime.includes('matroska') ? 'mkv' : 'webm';
  const name = `rec-${type.replace(/[^a-z0-9]+/gi, '_')}.${ext}`;
  fs.writeFileSync(path.join(out, name), Buffer.from(file.base64, 'base64'));
  written.push({ type, recorderMime: file.mime, size: file.size, file: name });
}
fs.writeFileSync(path.join(out, 'mediarecorder.json'), JSON.stringify({ userAgent: report.userAgent, supported: report.supported, written }, null, 2));
console.log(JSON.stringify({ userAgent: report.userAgent, supported: report.supported, written }, null, 2));
await context.close();
process.exit(0);
