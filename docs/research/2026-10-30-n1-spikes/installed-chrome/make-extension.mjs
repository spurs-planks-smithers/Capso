// Writes the throwaway extension manifest with a fixed throwaway key and prints its ID.
// The key is generated once and discarded with the extension. It is not Pilot's or Dev's key.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const manifestPath = path.join(here, 'ext', 'manifest.json');
const existing = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : null;
let key = existing?.key;
if (!key) {
  const { publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  key = publicKey.export({ type: 'spki', format: 'der' }).toString('base64');
}
const der = Buffer.from(key, 'base64');
const id = [...crypto.createHash('sha256').update(der).digest('hex').slice(0, 32)].map((c) => String.fromCharCode(97 + parseInt(c, 16))).join('');
fs.mkdirSync(path.join(here, 'ext'), { recursive: true });
fs.writeFileSync(manifestPath, JSON.stringify({
  manifest_version: 3,
  name: 'N1 throwaway (remove me)',
  version: '0.0.1',
  description: 'Throwaway probe for issue 178. Click once, then remove it.',
  key,
  permissions: ['nativeMessaging', 'activeTab', 'scripting', 'alarms'],
  background: { service_worker: 'sw.js' },
  action: { default_title: 'N1 throwaway: click once' },
}, null, 2) + '\n');
console.log(id);
