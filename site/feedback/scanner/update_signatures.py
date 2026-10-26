"""Trusted updater. It has no input files or upload-store access.

Run in a separate trusted process with internet access. Publish its immutable
objects before publishing manifest.json in the private SIGNATURES bucket.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

NAMES=('main.cvd','daily.cvd','bytecode.cvd')


def verify_database(file):
    if not file.is_file() or file.is_symlink() or not 1<=file.stat().st_size<=300_000_000:
        raise SystemExit('A signed database is missing or invalid.')
    verified=subprocess.run(['sigtool','--info',str(file)],stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,timeout=30,check=False)
    if verified.returncode or b'Verification OK' not in verified.stdout:
        raise SystemExit('Database signature verification failed.')


def prepare_seed(source,target):
    source=source.resolve()
    if not source.is_dir(): raise SystemExit('The seed directory is unavailable.')
    for name in NAMES: verify_database(source/name)
    for name in NAMES: shutil.copyfile(source/name,target/name)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--seed',type=Path,help='Existing verified CVD files from the private mirror')
    args=parser.parse_args()
    output=args.output.resolve()
    if output.exists(): raise SystemExit('Use a new output directory.')
    with tempfile.TemporaryDirectory(prefix='nextshot-definitions-') as temporary:
        folder=Path(temporary); config=folder/'freshclam.conf'
        if args.seed is not None: prepare_seed(args.seed,folder)
        config.write_text(f'DatabaseDirectory {folder}\nDatabaseMirror database.clamav.net\nScriptedUpdates no\nChecks 1\nDNSDatabaseInfo current.cvd.clamav.net\n')
        fresh=subprocess.run(['freshclam','--config-file',str(config),'--stdout'],stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE,timeout=300,check=False)
        if fresh.returncode!=0: raise SystemExit('Signature refresh failed. Nothing was published.')
        manifest=[]
        for name in NAMES:
            file=folder/name
            verify_database(file)
            data=file.read_bytes(); digest=hashlib.sha256(data).hexdigest()
            manifest.append({'name':name,'sha256':digest,'bytes':len(data)})
        output.mkdir(mode=0o700,parents=True)
        for item in manifest:
            dest=output/'definitions'/item['sha256']/item['name']
            dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes((folder/item['name']).read_bytes())
        (output/'manifest.json').write_text(json.dumps({'version':1,'updatedAt':datetime.now(timezone.utc).isoformat(),'files':manifest},indent=2)+'\n')
        print('Verified signature objects prepared. Publish manifest.json last.')


if __name__=='__main__': main()
