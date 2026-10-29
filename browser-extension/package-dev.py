#!/usr/bin/env python3
"""Build a deterministic local Dev extension ZIP. Never install or publish it."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXTENSION = ROOT / 'browser-extension'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pilot', action='store_true', help='Build the isolated browser-only friend pilot.')
args = parser.parse_args()
PILOT = args.pilot
BUILD = ROOT / ('build/chrome-pilot' if PILOT else 'build/chrome-extension')
OUTPUT = ROOT / ('build/friend-pilot' if PILOT else 'build/browser-extension-package')
EXTENSION_ID = 'ffnikmhbnlgmfeniemlmfniihooipmcd' if PILOT else 'ghmidcmcjigfckaiopacgpfaffofgjel'
PREFIX = 'Nextshot-Pilot' if PILOT else 'Nextshot-Dev-extension'


def run(*args):
    subprocess.run(args, cwd=EXTENSION, check=True)


def digest(data):
    return hashlib.sha256(data).hexdigest()


# Clear only this script's known generated directory. Stale output cannot enter a ZIP.
if BUILD.exists():
    if BUILD.is_symlink():
        raise SystemExit('Refuse a linked build directory.')
    shutil.rmtree(BUILD)
run('npm', 'ci', '--include=dev')
run('npm', 'run', 'check')
run('npm', 'run', 'build', *(['--', '--pilot'] if PILOT else []))
manifest = json.loads((BUILD / 'manifest.json').read_text())
key_digest = hashlib.sha256(base64.b64decode(manifest['key'], validate=True)).digest()[:16]
actual_id = ''.join(chr(ord('a') + nibble) for byte in key_digest for nibble in (byte >> 4, byte & 15))
if actual_id != EXTENSION_ID or manifest.get('name') != ('Nextshot Pilot' if PILOT else 'Nextshot Dev') or manifest.get('manifest_version') != 3:
    raise SystemExit('Refuse a changed extension identity.')
if set(manifest.get('permissions', [])) != {'activeTab', 'scripting', 'storage'}:
    raise SystemExit('Review changed required permissions before packaging.')
if set(manifest.get('optional_permissions', [])) - (set() if PILOT else {'nativeMessaging', 'tabCapture', 'webRequest', 'downloads', 'clipboardWrite', 'offscreen', 'identity'}):
    raise SystemExit('Review changed optional permissions before packaging.')
if manifest.get('host_permissions') or set(manifest.get('optional_host_permissions', [])) != {'http://*/*', 'https://*/*'}:
    raise SystemExit('Review changed host access before packaging.')
if any(key in manifest for key in ['externally_connectable', 'update_url']):
    raise SystemExit('Review external access or update endpoints before packaging.')

files = {}
network_literals = set()
secret_pattern = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}|\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}')
for source in sorted(BUILD.rglob('*')):
    if source.is_symlink():
        raise SystemExit('Refuse a linked build asset.')
    if not source.is_file():
        continue
    relative = source.relative_to(BUILD)
    if source.suffix.lower() not in {'.js', '.html', '.css', '.json', '.png', '.svg', '.webp', '.jpg', '.jpeg', '.ico', '.woff2', '.gif'}:
        raise SystemExit(f'Review unexpected build asset: {relative}')
    if any(part.startswith('.') for part in relative.parts):
        raise SystemExit(f'Refuse hidden build asset: {relative}')
    data = source.read_bytes()
    if secret_pattern.search(data):
        raise SystemExit(f'Potential secret in build asset: {relative}')
    files[PREFIX + '/extension/' + relative.as_posix()] = data
    if source.suffix in {'.js', '.html', '.css', '.json'}:
        network_literals.update(re.findall(r'https?://[^\s\x00-\x20"\'<>`\\)]+', data.decode('utf-8')))
if not files or not (BUILD / ('pilot-background.js' if PILOT else 'background.js')).is_file() or not (BUILD / 'popup.html').is_file():
    raise SystemExit('Build output is incomplete.')
if PILOT:
    if "connect-src 'self' data: blob:" not in manifest.get('content_security_policy', {}).get('extension_pages', ''):
        raise SystemExit('Pilot must block remote extension-page requests.')
    if set(manifest.get('commands', {})) != {'capture'}:
        raise SystemExit('Pilot must expose ordinary capture only.')
    for name, data in files.items():
        if name.endswith('.js') and re.search(rb'sendNativeMessage|connectNative|launchWebAuthFlow|api\.typesafe\.ai|jev\.nextshot\.dev', data):
            raise SystemExit(f'Unexpected transport in pilot: {name}')
    for name in ['offscreen.html', 'rolling.html', 'recording.html']:
        if (BUILD / name).exists():
            raise SystemExit('Unexpected feature page in pilot.')
    files[PREFIX + '/START-HERE.txt'] = (EXTENSION / 'PILOT.txt').read_bytes()
    files[PREFIX + '/TRY-THIS.txt'] = (EXTENSION / 'TRY-THIS.txt').read_bytes()
else:
    files[PREFIX + '/INSTALL.md'] = (EXTENSION / 'INSTALL.md').read_bytes()
    files[PREFIX + '/tools/register-browser-host.py'] = (ROOT / 'scripts/register-browser-host.py').read_bytes()
files[PREFIX + '/LICENSE.txt'] = (ROOT / 'LICENSE').read_bytes()
for name, data in files.items():
    if secret_pattern.search(data):
        raise SystemExit(f'Potential secret in package file: {name}')
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
dirty = bool(subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no',
    '--', 'browser-extension', 'scripts/register-browser-host.py'], cwd=ROOT, text=True).strip())
audit = {
    'channel': 'browser-pilot' if PILOT else 'dev', 'extensionID': EXTENSION_ID, 'sourceCommit': revision, 'sourceDirty': dirty,
    'manifest': manifest, 'networkLiterals': sorted(network_literals),
    'files': {name: {'bytes': len(data), 'sha256': digest(data)} for name, data in sorted(files.items())},
}
files[PREFIX + '/package-audit.json'] = (json.dumps(audit, indent=2, sort_keys=True) + '\n').encode()
OUTPUT.mkdir(parents=True, exist_ok=True)
archive = OUTPUT / (f"Nextshot-Pilot-{manifest['version']}-{revision[:7]}{'-dirty' if dirty else ''}.zip" if PILOT else f"Nextshot-Dev-extension-{manifest['version']}.zip")
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
    for name, data in sorted(files.items()):
        info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        package.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
with zipfile.ZipFile(archive) as package:
    if package.testzip() is not None or set(package.namelist()) != set(files):
        raise SystemExit('Archive verification failed.')
checksum = digest(archive.read_bytes())
archive.with_suffix('.zip.sha256').write_text(f'{checksum}  {archive.name}\n')
print(f"{'Pilot' if PILOT else 'Dev'} package: {archive}")
print(f'SHA-256: {checksum}')
print(f'Extension ID: {EXTENSION_ID}')
print(f'{len(files)} files. No browser installation or publication occurred.')
