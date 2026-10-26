"""Trusted updater. It has no input files or upload-store access.

Run in a separate trusted process with internet access. Publish its immutable
objects before publishing manifest.json in the private SIGNATURES bucket.
"""
import argparse
import hashlib
import json
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

NAMES=('main.cvd','daily.cvd','bytecode.cvd')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    output=args.output.resolve()
    if output.exists(): raise SystemExit('Use a new output directory.')
    with tempfile.TemporaryDirectory(prefix='nextshot-definitions-') as temporary:
        folder=Path(temporary); config=folder/'freshclam.conf'
        config.write_text(f'DatabaseDirectory {folder}\nDatabaseMirror database.clamav.net\nScriptedUpdates no\nChecks 1\nDNSDatabaseInfo current.cvd.clamav.net\n')
        fresh=subprocess.run(['freshclam','--config-file',str(config),'--stdout'],stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE,timeout=300,check=False)
        if fresh.returncode!=0: raise SystemExit('Signature refresh failed. Nothing was published.')
        manifest=[]
        for name in NAMES:
            file=folder/name
            if not file.is_file(): raise SystemExit('A signed database is missing.')
            verified=subprocess.run(['sigtool','--info',str(file)],stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE,timeout=30,check=False)
            if verified.returncode or b'Verification OK' not in verified.stdout:
                raise SystemExit('Database signature verification failed.')
            data=file.read_bytes(); digest=hashlib.sha256(data).hexdigest()
            manifest.append({'name':name,'sha256':digest,'bytes':len(data)})
        output.mkdir(mode=0o700,parents=True)
        for item in manifest:
            dest=output/'definitions'/item['sha256']/item['name']
            dest.parent.mkdir(parents=True,exist_ok=True); dest.write_bytes((folder/item['name']).read_bytes())
        (output/'manifest.json').write_text(json.dumps({'version':1,'updatedAt':datetime.now(timezone.utc).isoformat(),'files':manifest},indent=2)+'\n')
        print('Verified signature objects prepared. Publish manifest.json last.')


if __name__=='__main__': main()
