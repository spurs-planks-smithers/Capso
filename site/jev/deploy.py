#!/usr/bin/env python3
"""Manage the isolated invited Jev pilot. Credentials remain in process memory."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent
ACCOUNT = '2afca1b8aab7ec4024bdb7cb2fec47c0'
ZONE = 'ecc8cb0c8feb5e3a066062f76dfdbd49'
HOST = 'jev.nextshot.dev'
NAME = 'nextshot-jev-pilot'
OWNER = 'drewschulz1@gmail.com'
CONFIG = ROOT / 'wrangler.jsonc'


def credential(name):
    value = subprocess.run(['security', 'find-generic-password', '-s', name, '-w'],
        capture_output=True, check=True).stdout.strip()
    if len(value) < 32:
        raise RuntimeError('Credential length check failed')
    return value.decode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['setup', 'deploy', 'status', 'secret', 'pause'])
    parser.add_argument('--existing-account-login', action='store_true',
        help='Prepare only the invited account-owner pilot with the existing Cloudflare login.')
    args = parser.parse_args()
    site = credential('CLOUDFLARE_API_TOKEN_NEXTSHOT')
    setup = credential('CLOUDFLARE_API_TOKEN_NEXTSHOT_FEEDBACK')

    def api(path, method='GET', body=None, access=False):
        request = urllib.request.Request('https://api.cloudflare.com/client/v4/' + path,
            method=method, headers={'Authorization': 'Bearer ' + (setup if access else site),
                'Content-Type': 'application/json'},
            data=None if body is None else json.dumps(body).encode())
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                value = json.load(response)
        except urllib.error.HTTPError as error:
            value=json.loads(error.read()); codes=[item.get('code') for item in value.get('errors', [])]
            raise RuntimeError('Cloudflare HTTP ' + str(error.code) + ' at ' + path + ', codes ' + str(codes)) from None
        if not value.get('success'):
            raise RuntimeError('Cloudflare operation failed')
        return value['result']

    account = 'accounts/' + ACCOUNT
    config = json.loads(CONFIG.read_text())
    if args.mode == 'setup':
        providers = api(account + '/access/identity_providers', access=True)
        pin = None if args.existing_account_login else next((p for p in providers if p['type'] == 'onetimepin'), None)
        if not pin and not args.existing_account_login:
            pin = api(account + '/access/identity_providers', 'POST',
                {'name': 'Nextshot invited email PIN', 'type': 'onetimepin', 'config': {}}, True)
        apps = api(account + '/access/apps?per_page=100', access=True)
        app = next((a for a in apps if a.get('domain') == HOST + '/auth/authorize'), None)
        if not app:
            app = api(account + '/access/apps', 'POST', {'type': 'self_hosted',
                'name': 'Nextshot Jev invited pilot', 'domain': HOST + '/auth/authorize',
                'allowed_idps': [pin['id']] if pin else [], 'auto_redirect_to_identity': bool(pin),
                'app_launcher_visible': False, 'session_duration': '1h'}, True)
        policies = api(account + '/access/apps/' + app['id'] + '/policies', access=True)
        if not policies:
            api(account + '/access/apps/' + app['id'] + '/policies', 'POST',
                {'name': 'Invited owner only', 'decision': 'allow',
                    'include': [{'email': {'email': OWNER}}],
                    'require': [] if pin else [{'cloudflare_account_member': {'account_id': ACCOUNT}}]}, True)
        databases = api(account + '/d1/database?per_page=100')
        database = next((d for d in databases if d['name'] == NAME), None)
        if not database:
            database = api(account + '/d1/database', 'POST', {'name': NAME})
        database_id = database['uuid']
        query = account + '/d1/database/' + database_id + '/query'
        existing = api(query, 'POST', {'sql': "SELECT name FROM sqlite_master WHERE type='table' AND name='users'"})
        if not existing[0]['results']:
            api(query, 'POST', {'sql': (ROOT / 'schema.sql').read_text()})
        api(query, 'POST', {'sql': 'INSERT OR IGNORE INTO invitations(email_hash,user_id,enabled,monthly_limit) VALUES(?,?,1,?)',
            'params': [hashlib.sha256(OWNER.encode()).hexdigest(), 'owner-pilot', 5000000]})
        config['account_id'] = ACCOUNT
        config['d1_databases'][0]['database_id'] = database_id
        config['vars'].update(SERVICE_ISSUER='https://' + HOST,
            ACCESS_TEAM_DOMAIN='shrill-math-8862.cloudflareaccess.com', ACCESS_AUDIENCE=app['aud'],
            PROCESSING_ENABLED='false', BILLING_BOUND_VERIFIED='false')
        CONFIG.write_text(json.dumps(config, indent=2) + '\n')
        print('Separate database, Access application, and owner invitation configured. Processing remains disabled.')

    if not config['d1_databases'][0]['database_id'] or not config['vars']['ACCESS_AUDIENCE']:
        raise RuntimeError('Run setup first')
    apps = api(account + '/access/apps?per_page=100', access=True)
    app = next(a for a in apps if a.get('aud') == config['vars']['ACCESS_AUDIENCE'])
    policies = api(account + '/access/apps/' + app['id'] + '/policies', access=True)
    providers = api(account + '/access/identity_providers', access=True)
    pins = {p['id'] for p in providers if p['type'] == 'onetimepin'}
    pin_login = bool(app.get('allowed_idps')) and not set(app['allowed_idps']) - pins
    owner_login = not app.get('allowed_idps') and len(policies) == 1 and policies[0].get('require') == [{'cloudflare_account_member': {'account_id': ACCOUNT}}]
    if app.get('domain') != HOST + '/auth/authorize' or not (pin_login or owner_login):
        raise RuntimeError('Exact verified-email Access scope is required')
    if len(policies) != 1 or policies[0].get('decision') != 'allow' or policies[0].get('include') != [{'email': {'email': OWNER}}] or policies[0].get('exclude') or (pin_login and policies[0].get('require')):
        raise RuntimeError('Exact invitation policy is required')
    environment = {k: os.environ[k] for k in ['PATH', 'HOME', 'USER', 'LOGNAME', 'LANG', 'TMPDIR'] if k in os.environ}
    environment.update(CLOUDFLARE_API_TOKEN=site, CI='true', WRANGLER_SEND_METRICS='false')
    command = ['node', str(ROOT / 'node_modules/wrangler/bin/wrangler.js')]
    if args.mode in {'deploy', 'pause'}:
        if args.mode == 'pause':
            config['vars']['PROCESSING_ENABLED'] = 'false'
            CONFIG.write_text(json.dumps(config, indent=2) + '\n')
        subprocess.run(command + ['deploy', '--env-file', '/dev/null'], cwd=ROOT,
            env=environment, stdin=subprocess.DEVNULL, check=True)
        domains = api(account + '/workers/domains')
        prior = next((d for d in domains if d['hostname'] == HOST), None)
        if prior and prior['service'] != NAME:
            raise RuntimeError('Hostname belongs to another service')
        if not prior:
            records = api('zones/' + ZONE + '/dns_records?name=' + HOST)
            if records:
                raise RuntimeError('Hostname already has DNS records')
            api(account + '/workers/domains', 'PUT',
                {'hostname': HOST, 'service': NAME, 'zone_id': ZONE, 'environment': 'production'})
    if args.mode == 'secret':
        key = credential('TYPESAFE_API_KEY_NEXTSHOT')
        subprocess.run(command + ['secret', 'put', 'TYPESAFE_API_KEY', '--env-file', '/dev/null'],
            cwd=ROOT, env=environment, input=key.encode(), check=True)
        print('Nextshot project credential stored as an encrypted Worker binding. No key file created.')
    if args.mode != 'setup':
        settings = api(account + '/workers/scripts/' + NAME + '/settings')
        controls = {b['name']: b.get('text') for b in settings['bindings']
            if b['name'] in {'PROCESSING_ENABLED', 'BILLING_BOUND_VERIFIED'}}
        if set(controls) != {'PROCESSING_ENABLED', 'BILLING_BOUND_VERIFIED'}:
            raise RuntimeError('Missing processing controls')
        print(json.dumps({'worker': NAME, 'authPath': app['domain'], 'loginMethod': 'email-pin' if pin_login else 'existing-cloudflare-account',
            'ownerOnly': True, 'controls': controls}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit('Jev pilot operation failed: ' + str(error)) from None
