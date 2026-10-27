#!/usr/bin/env python3
"""Deploy fixed Nextshot intake modes. This never builds or publishes a Mac app."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SERVICE = ROOT / 'site/feedback'
ACCOUNT = '2afca1b8aab7ec4024bdb7cb2fec47c0'
APP = 'abe8db0b-1a5b-4d44-89ef-3682a6db1d8b'
HOST = 'feedback.nextshot.dev'
OWNER = 'drewschulz1@gmail.com'
FLAGS = {'INTAKE_ENABLED', 'NATIVE_ENABLED', 'PROCESSING_ENABLED',
         'AI_SCREENING_ENABLED', 'EMAIL_ENABLED', 'NOTIFICATIONS_ENABLED'}
IMAGE = 'registry.cloudflare.com/' + ACCOUNT + '/nextshot-feedback-scanner-scanner@sha256:582ec345c20a1db2eddb5193a0b371c15442ad656af59ba7ef1129ef622762e1'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['status', 'web', 'native', 'pause'])
    args = parser.parse_args()
    credential = subprocess.run(['security', 'find-generic-password', '-s',
        'CLOUDFLARE_API_TOKEN_NEXTSHOT_FEEDBACK', '-w'], capture_output=True,
        text=True, check=True).stdout.strip()
    if len(credential) < 32:
        raise RuntimeError('Feedback deployment credential is unavailable')

    def api(path):
        request = urllib.request.Request('https://api.cloudflare.com/client/v4/accounts/' + ACCOUNT + path,
            headers={'Authorization': 'Bearer ' + credential})
        with urllib.request.urlopen(request, timeout=30) as response:
            value = json.load(response)
        if not value.get('success'):
            raise RuntimeError('Cloudflare verification failed')
        return value['result']

    def access():
        application = api('/access/apps/' + APP)
        policies = api('/access/apps/' + APP + '/policies')
        if application.get('domain') not in {HOST, HOST + '/review'}:
            raise RuntimeError('Review Access scope is not recognized')
        if application.get('destinations') != [{'type': 'public', 'uri': application['domain']}] or application.get('self_hosted_domains') != [application['domain']]:
            raise RuntimeError('Review Access destinations differ')
        if len(policies) != 1 or policies[0].get('decision') != 'allow' or policies[0].get('include') != [{'email': {'email': OWNER}}] or policies[0].get('exclude') or policies[0].get('require'):
            raise RuntimeError('Exact owner Access policy is required')
        return application

    application = access()
    if args.mode != 'status':
        config = json.loads((SERVICE / 'wrangler.production.jsonc').read_text())
        if application.get('aud') != config['vars']['ACCESS_AUD']:
            raise RuntimeError('Review token audience differs')
        if config['name'] != 'nextshot-feedback' or config['account_id'] != ACCOUNT:
            raise RuntimeError('Unexpected Worker identity')
        if {b['bucket_name'] for b in config['r2_buckets']} != {'nextshot-feedback-raw', 'nextshot-feedback-rebuilt', 'nextshot-feedback-signatures'}:
            raise RuntimeError('Unexpected storage binding')
        if config['containers'][0]['images']['scanner'] != {'image': IMAGE}:
            raise RuntimeError('Approved scanner digest is required')
        if set(k for k in config['vars'] if k.endswith('_ENABLED')) != FLAGS:
            raise RuntimeError('Unexpected launch controls')
        if config['send_email'] != [{'name': 'CONTACT_NOTIFY', 'destination_address': OWNER}] or config['workers_dev'] or config['preview_urls']:
            raise RuntimeError('Unexpected public or mail binding')
        config['vars']['EMAIL_ENABLED'] = 'false'
        config['vars']['NATIVE_ENABLED'] = 'true' if args.mode == 'native' else 'false'
        if args.mode == 'pause':
            for flag in FLAGS:
                config['vars'][flag] = 'false'
        config['main'] = str(SERVICE / 'src/worker.js')
        config['assets']['directory'] = str(SERVICE / 'public')
        allowed = ['PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'TMPDIR']
        environment = {name: os.environ[name] for name in allowed if name in os.environ}
        environment.update(CLOUDFLARE_API_TOKEN=credential, CI='true', WRANGLER_SEND_METRICS='false')
        with tempfile.TemporaryDirectory(prefix='nextshot-feedback-deploy-') as temporary:
            path = Path(temporary) / 'wrangler.json'
            path.write_text(json.dumps(config))
            subprocess.run(['node', str(SERVICE / 'node_modules/wrangler/bin/wrangler.js'),
                'deploy', '--config', str(path), '--env-file', '/dev/null'],
                env=environment, cwd=SERVICE, stdin=subprocess.DEVNULL, check=True)
        application = access()
    settings = api('/workers/scripts/nextshot-feedback/settings')
    flags = {b['name']: b.get('text') for b in settings['bindings'] if b['name'] in FLAGS}
    if set(flags) != FLAGS:
        raise RuntimeError('Launch control verification is incomplete')
    if args.mode != 'status' and flags != {name: config['vars'][name] for name in FLAGS}:
        raise RuntimeError('Deployed launch controls differ')
    if {b['name'] for b in settings['bindings'] if b['type'] == 'secret_text'} != {'INTAKE_SECRET', 'TURNSTILE_SECRET'}:
        raise RuntimeError('Required secret bindings are absent')
    print(json.dumps({'worker': 'nextshot-feedback', 'accessDomain': application['domain'], 'ownerPolicyVerified': True, 'flags': flags}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit('Feedback deployment failed: ' + type(error).__name__) from None
