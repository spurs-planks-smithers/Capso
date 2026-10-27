"""Create a private build context after the operator has approved Meta access."""
import argparse
import hashlib
import json
import os
import shutil
import stat
import tempfile
from pathlib import Path

MODEL = 'meta-llama/Llama-Prompt-Guard-2-22M'
REVISION = '11614a155199674a0a95e6602d6ab0417b790ed0'
# Source: https://huggingface.co/api/models/meta-llama/Llama-Prompt-Guard-2-22M/revision/11614a155199674a0a95e6602d6ab0417b790ed0?blobs=true
# Public Hugging Face revision API metadata. Git blob IDs include
# the Git object header. The safetensors digest is the upstream LFS content hash.
EXPECTED_ARTIFACTS = {
    'LICENSE': {'size': 7554, 'blobId': 'be16bdcf5eac8030d7d92c9cc0503480471263c4'},
    'USE_POLICY.md': {'size': 5796, 'blobId': 'b3f1fcefae19f6396ba6081636479a3b8e39d5f7'},
    'config.json': {'size': 870, 'blobId': 'dee8822dafaea58a27fdbe96eb3b6be58472c745'},
    'model.safetensors': {'size': 283347432, 'sha256': '5120e30bcd536ce285345d9ec104bea6bd6e8f94365b99a340c764f417ea5fa1'},
    'special_tokens_map.json': {'size': 286, 'blobId': '2c9cb07c8fdeeb5ac3ceafb170592e990b204dcd'},
    'tokenizer.json': {'size': 8657051, 'blobId': 'cbff3984b6c696631375e5aa3638183791f3dfc3'},
    'tokenizer_config.json': {'size': 1284, 'blobId': '13d6406af565bd9e59dd649afd4c2b48bddb6a4c'},
}


def verified_snapshot(snapshot, staged):
    if not EXPECTED_ARTIFACTS or not snapshot.is_dir() or {p.name for p in snapshot.iterdir()} != set(EXPECTED_ARTIFACTS):
        raise ValueError('Snapshot must contain exactly the approved artifacts.')
    manifest = {}
    for name, expected in EXPECTED_ARTIFACTS.items():
        # Follow HF cache symlinks, then inspect the opened object. Hash and stage
        # the same bytes so replacing a source path cannot bypass verification.
        descriptor = os.open(snapshot / name, os.O_RDONLY | os.O_NONBLOCK)
        with os.fdopen(descriptor, 'rb') as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size != expected['size']:
                raise ValueError('Artifact type or byte count differs: ' + name)
            sha256 = hashlib.sha256()
            blob = hashlib.sha1(b'blob ' + str(expected['size']).encode() + b'\0')
            count = 0
            with (staged / name).open('xb') as output:
                while chunk := source.read(1024 * 1024):
                    count += len(chunk)
                    if count > expected['size']:
                        raise ValueError('Artifact grew while reading: ' + name)
                    sha256.update(chunk)
                    blob.update(chunk)
                    output.write(chunk)
            digest = sha256.hexdigest() if 'sha256' in expected else blob.hexdigest()
            if count != expected['size'] or digest != expected.get('sha256', expected.get('blobId')):
                raise ValueError('Artifact content differs from pinned upstream: ' + name)
            manifest[name] = sha256.hexdigest()
    return manifest


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-context', required=True, type=Path,
                        help='New private build folder outside any Git checkout')
    parser.add_argument('--local-snapshot', type=Path,
                        help='Approved local artifacts, checked against the pinned upstream revision')
    args = parser.parse_args(argv)
    target = args.build_context.resolve()
    source = Path(__file__).resolve().parent
    if target.exists() or args.build_context.is_symlink() or any((p / '.git').exists() for p in (target, *target.parents)):
        raise SystemExit('Use a new private folder outside the Git checkout.')
    if args.local_snapshot is not None:
        snapshot = args.local_snapshot
    else:
        # Read HF_TOKEN from the process environment only. Never print or persist it.
        from huggingface_hub import snapshot_download
        snapshot = Path(snapshot_download(MODEL, revision=REVISION,
                                         allow_patterns=list(EXPECTED_ARTIFACTS)))
    try:
        with tempfile.TemporaryDirectory(prefix='nextshot-model-') as folder:
            staged = Path(folder)
            manifest = verified_snapshot(snapshot, staged)
            # No private context exists until every upstream content check passes.
            target.mkdir(mode=0o700)
            try:
                shutil.copytree(source, target, dirs_exist_ok=True,
                                ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '.venv', 'tests'))
                target.chmod(0o700)
                model = target / 'model'
                for file in staged.iterdir():
                    shutil.copyfile(file, model / file.name)
                (model / 'model-manifest.json').write_text(json.dumps({
                    'model': MODEL, 'revision': REVISION, 'files': manifest}, indent=2) + '\n')
            except BaseException:
                shutil.rmtree(target)
                raise
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
    print('Private model build context prepared. Credentials were not copied.')


if __name__ == '__main__':
    main()
