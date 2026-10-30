#!/usr/bin/env python3
"""Register only the signed Dev helper for the fixed unpacked Dev extension."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path.home() / 'Applications/Nextshot Dev.app'
if len(sys.argv) > 1:
    app = Path(sys.argv[1]).expanduser().resolve()
with (app / 'Contents/Info.plist').open('rb') as source:
    info = plistlib.load(source)
if info.get('CFBundleIdentifier') != 'com.drewschulz.nextshot.dev':
    raise SystemExit('Only Nextshot Dev registration is supported by this pilot command.')
helper = app / 'Contents/Helpers/NextshotBrowserHost'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(helper)], check=True)
folder = Path.home() / 'Library/Application Support/Google/Chrome/NativeMessagingHosts'
folder.mkdir(parents=True, exist_ok=True)
manifest = {
    'name': 'com.drewschulz.nextshot.dev.browser',
    'description': 'Nextshot Dev local browser save',
    'path': str(helper),
    'type': 'stdio',
    'allowed_origins': ['chrome-extension://ghmidcmcjigfckaiopacgpfaffofgjel/'],
}
target = folder / (manifest['name'] + '.json')
temporary = target.with_suffix('.tmp')
temporary.write_text(json.dumps(manifest, indent=2) + '\n')
os.chmod(temporary, 0o600)
temporary.replace(target)
print(f'Registered the signed Dev helper: {target}')
print('Native browser import remains off until its Dev trial flag is enabled.')
