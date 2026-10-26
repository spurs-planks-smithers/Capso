#!/usr/bin/env python3
"""Refresh only the private Nextshot malware-definition mirror.

The runtime credential must have item access to nextshot-feedback-signatures
only. This process has no submission data or upload-store access.
"""
import argparse
import datetime
import hashlib
import hmac
import json
import os
import re
import subprocess
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ACCOUNT = '2afca1b8aab7ec4024bdb7cb2fec47c0'
BUCKET = 'nextshot-feedback-signatures'
NAMES = ('main.cvd', 'daily.cvd', 'bytecode.cvd')
MAX_DATABASE = 300_000_000


def validate_key(key):
    if key != 'manifest.json' and not re.fullmatch(
        r'definitions/[a-f0-9]{64}/(?:main|daily|bytecode)\.cvd', key
    ):
        raise ValueError('Signature key is outside the fixed mirror namespace')


def manifest_files(manifest):
    files = manifest.get('files') if isinstance(manifest, dict) else None
    if (manifest.get('version') != 1 or not isinstance(files, list)
            or len(files) != 3 or {item.get('name') for item in files} != set(NAMES)):
        raise ValueError('Invalid signature manifest')
    for item in files:
        if (not re.fullmatch(r'[a-f0-9]{64}', item.get('sha256', ''))
                or type(item.get('bytes')) is not int
                or not 0 < item['bytes'] <= MAX_DATABASE):
            raise ValueError('Invalid signature object')
    return files


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


class Mirror:
    def __init__(self, token):
        self.opener = urllib.request.build_opener(NoRedirect)
        request = urllib.request.Request(
            f'https://api.cloudflare.com/client/v4/accounts/{ACCOUNT}/tokens/verify',
            headers={'Authorization': 'Bearer ' + token},
        )
        with self.opener.open(request, timeout=20) as response:
            result = json.load(response)
        self.key_id = result['result']['id']
        if not result.get('success') or not re.fullmatch(r'[a-f0-9]{32}', self.key_id):
            raise ValueError('Signature credential verification failed')
        self.secret = hashlib.sha256(token.encode()).hexdigest()

    def request(self, method, key, body=b''):
        validate_key(key)
        host = f'{ACCOUNT}.r2.cloudflarestorage.com'
        path = f'/{BUCKET}/{key}'
        now = datetime.datetime.now(datetime.timezone.utc)
        date = now.strftime('%Y%m%d')
        timestamp = now.strftime('%Y%m%dT%H%M%SZ')
        body_hash = hashlib.sha256(body).hexdigest()
        headers = {
            'host': host,
            'x-amz-content-sha256': body_hash,
            'x-amz-date': timestamp,
        }
        signed = ';'.join(sorted(headers))
        canonical_headers = ''.join(name + ':' + headers[name] + '\n' for name in sorted(headers))
        canonical = '\n'.join([method, path, '', canonical_headers, signed, body_hash])
        scope = f'{date}/auto/s3/aws4_request'
        sign_text = '\n'.join(['AWS4-HMAC-SHA256', timestamp, scope, hashlib.sha256(canonical.encode()).hexdigest()])
        signing_key = ('AWS4' + self.secret).encode()
        for value in (date, 'auto', 's3', 'aws4_request'):
            signing_key = hmac.new(signing_key, value.encode(), hashlib.sha256).digest()
        signature = hmac.new(signing_key, sign_text.encode(), hashlib.sha256).hexdigest()
        headers['Authorization'] = f'AWS4-HMAC-SHA256 Credential={self.key_id}/{scope}, SignedHeaders={signed}, Signature={signature}'
        request = urllib.request.Request('https://' + host + path, data=body if method == 'PUT' else None, headers=headers, method=method)
        return self.opener.open(request, timeout=180)

    def get(self, key, maximum):
        try:
            with self.request('GET', key) as response:
                data = response.read(maximum + 1)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            raise
        if len(data) > maximum:
            raise ValueError('Signature mirror response exceeds its limit')
        return data

    def put(self, key, data):
        with self.request('PUT', key, data):
            pass


def restore_seed(store, folder):
    data = store.get('manifest.json', 4096)
    if data is None:
        return False
    manifest = json.loads(data)
    for item in manifest_files(manifest):
        data = store.get(f'definitions/{item["sha256"]}/{item["name"]}', item['bytes'])
        if data is None or len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError('Existing signature object failed verification')
        (folder / item['name']).write_bytes(data)
    return True


def publish(folder, store):
    manifest_data = (folder / 'manifest.json').read_bytes()
    if len(manifest_data) > 4096:
        raise ValueError('Manifest exceeds its limit')
    files = manifest_files(json.loads(manifest_data))
    # Validate every file before the first network write.
    for item in files:
        file = folder / 'definitions' / item['sha256'] / item['name']
        if file.is_symlink() or not file.is_file() or file.stat().st_size != item['bytes']:
            raise ValueError('Signature object failed verification')
        if hashlib.sha256(file.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Signature object failed verification')
    for item in files:
        key = f'definitions/{item["sha256"]}/{item["name"]}'
        validate_key(key)
        store.put(key, (folder / key).read_bytes())
    # The pointer changes only after all immutable objects exist.
    store.put('manifest.json', manifest_data)


def refresh(store, updater, root):
    seed = root / 'seed'
    seed.mkdir(mode=0o700)
    has_seed = restore_seed(store, seed)
    output = root / 'verified'
    # The updater sees no R2 credential and accepts no uploaded content.
    allowed = ('PATH', 'HOME', 'LANG', 'LC_ALL', 'TMPDIR', 'SYSTEMROOT')
    environment = {key: os.environ[key] for key in allowed if key in os.environ}
    command = ['python3', str(updater), '--output', str(output)]
    if has_seed:
        command.extend(['--seed', str(seed)])
    subprocess.run(command, env=environment, check=True, timeout=420)
    publish(output, store)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--updater', type=Path, default=Path(__file__).resolve().parents[1] / 'site/feedback/scanner/update_signatures.py')
    arguments = parser.parse_args()
    token = os.environ.get('NEXTSHOT_SIGNATURES_API_TOKEN', '').strip()
    if not token:
        raise SystemExit('Signature mirror credential is unavailable')
    try:
        store = Mirror(token)
        with tempfile.TemporaryDirectory(prefix='nextshot-signature-refresh-') as temporary:
            refresh(store, arguments.updater, Path(temporary))
        print('Verified signature mirror refreshed. No submissions were accessed.')
    except Exception:
        raise SystemExit('Signature refresh failed. The previous manifest remains authoritative.') from None


if __name__ == '__main__':
    main()
