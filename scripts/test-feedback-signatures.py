"""Regression checks for the restricted public-definition publisher."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('feedback-signatures.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class Store:
    def __init__(self, fail_key=None):
        self.keys = []
        self.fail_key = fail_key

    def put(self, key, data):
        if key == self.fail_key:
            raise RuntimeError('injected transfer failure')
        self.keys.append(key)

    def get(self, key, maximum):
        return None


class PublisherTests(unittest.TestCase):
    def fixture(self, root):
        import hashlib
        files = []
        for name in publisher.NAMES:
            data = ('verified test definition ' + name).encode()
            digest = hashlib.sha256(data).hexdigest()
            target = root / 'definitions' / digest / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            files.append({'name': name, 'bytes': len(data), 'sha256': digest})
        manifest = {'version': 1, 'updatedAt': '2026-10-26T00:00:00+00:00', 'files': files}
        (root / 'manifest.json').write_text(json.dumps(manifest))
        return manifest

    def test_manifest_publishes_only_after_all_objects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            store = Store()
            publisher.publish(root, store)
            self.assertEqual(len(store.keys), 4)
            self.assertEqual(store.keys[-1], 'manifest.json')

    def test_failed_member_never_promotes_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.fixture(root)
            item = manifest['files'][1]
            store = Store(f'definitions/{item["sha256"]}/{item["name"]}')
            with self.assertRaises(RuntimeError):
                publisher.publish(root, store)
            self.assertNotIn('manifest.json', store.keys)

    def test_tampered_member_fails_before_promotion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.fixture(root)
            item = manifest['files'][0]
            (root / 'definitions' / item['sha256'] / item['name']).write_bytes(b'changed')
            store = Store()
            with self.assertRaises(ValueError):
                publisher.publish(root, store)
            self.assertEqual(store.keys, [])

    def test_restricted_key_space(self):
        for key in ('../release', 'latest.json', 'definitions/bad/main.cvd', 'quarantine/user.zip'):
            with self.assertRaises(ValueError):
                publisher.validate_key(key)

    def test_empty_mirror_bootstraps_without_a_seed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            updater = root / 'updater.py'
            updater.write_text('''import argparse, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--output',type=Path); p.add_argument('--seed'); a=p.parse_args()
if a.seed: raise SystemExit('An empty mirror must not supply a seed')
a.output.mkdir(); files=[]
for name in ('main.cvd','daily.cvd','bytecode.cvd'):
 data=('test '+name).encode(); digest=hashlib.sha256(data).hexdigest()
 target=a.output/'definitions'/digest/name; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)
 files.append({'name':name,'bytes':len(data),'sha256':digest})
(a.output/'manifest.json').write_text(json.dumps({'version':1,'files':files}))
''')
            store = Store()
            publisher.refresh(store, updater, root)
            self.assertEqual(store.keys[-1], 'manifest.json')


if __name__ == '__main__':
    unittest.main()
