"""Create a private build context after the operator has approved Meta access."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

MODEL='meta-llama/Llama-Prompt-Guard-2-22M'
REVISION='11614a155199674a0a95e6602d6ab0417b790ed0'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--build-context',required=True,type=Path,
                        help='New private build folder outside the Git checkout')
    args=parser.parse_args()
    target=args.build_context.resolve()
    source=Path(__file__).resolve().parent
    checkout=source.parents[2]
    if target.exists() or target.is_relative_to(checkout):
        raise SystemExit('Use a new private folder outside the Git checkout.')
    # Read HF_TOKEN from the process environment only. Never print or persist it.
    from huggingface_hub import snapshot_download
    snapshot=Path(snapshot_download(MODEL,revision=REVISION,
        allow_patterns=['*.json','*.safetensors','*.model','LICENSE','USE_POLICY.md','tokenizer*']))
    shutil.copytree(source,target,ignore=shutil.ignore_patterns('__pycache__','*.pyc','.venv','tests'))
    model=target/'model'
    manifest={}
    for file in snapshot.iterdir():
        if file.is_file() and (file.suffix in {'.json','.safetensors','.model'} or file.name in {'LICENSE','USE_POLICY.md'}):
            shutil.copyfile(file,model/file.name)
            manifest[file.name]=hashlib.sha256((model/file.name).read_bytes()).hexdigest()
    if not any(name.endswith('.safetensors') for name in manifest):
        shutil.rmtree(target)
        raise SystemExit('Approved safetensors artifacts are unavailable.')
    (model/'model-manifest.json').write_text(json.dumps({'model':MODEL,'revision':REVISION,'files':manifest},indent=2)+'\n')
    print('Private model build context prepared. Credentials were not copied.')


if __name__=='__main__': main()
