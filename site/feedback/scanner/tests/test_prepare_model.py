import hashlib
import os
import sys
import tempfile
from types import SimpleNamespace
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import prepare_model


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.snapshot = self.root / 'snapshot'
        self.snapshot.mkdir()
        self.expected = {}
        for name in ('config.json', 'model.safetensors'):
            content = b'fixture-' + name.encode()
            (self.snapshot / name).write_bytes(content)
            self.expected[name] = {'size': len(content)}
            if name.endswith('.safetensors'):
                self.expected[name]['sha256'] = hashlib.sha256(content).hexdigest()
            else:
                self.expected[name]['blobId'] = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
        self.target = self.root / 'context'

    def prepare(self):
        with patch.object(prepare_model, 'EXPECTED_ARTIFACTS', self.expected):
            prepare_model.main(['--build-context', str(self.target), '--local-snapshot', str(self.snapshot)])

    def test_valid_files_and_cache_symlinks_make_verified_manifest(self):
        original = self.snapshot / 'config.json'
        blob = self.root / 'cached-blob'
        original.rename(blob)
        original.symlink_to(blob)
        self.prepare()
        import json
        manifest = json.loads((self.target / 'model/model-manifest.json').read_text())
        self.assertEqual(manifest['files'], {name: hashlib.sha256((self.snapshot / name).read_bytes()).hexdigest() for name in self.expected})
        self.assertFalse((self.target / 'model/config.json').is_symlink())

    def test_invalid_artifacts_never_create_context(self):
        for failure in ('modified', 'missing', 'extra', 'directory', 'broken-link'):
            with self.subTest(failure=failure):
                config = self.snapshot / 'config.json'
                config.unlink()
                config.write_bytes(b'fixture-config.json')
                extra = self.snapshot / 'unapproved.py'
                extra.unlink(missing_ok=True)
                if failure == 'modified': config.write_bytes(b'fixture-config.jsom')
                elif failure == 'missing': config.unlink()
                elif failure == 'extra': extra.write_bytes(b'code')
                elif failure == 'directory':
                    config.unlink(); config.mkdir()
                else:
                    config.unlink(); config.symlink_to(self.root / 'missing')
                with self.assertRaises(SystemExit): self.prepare()
                self.assertFalse(self.target.exists())
                if config.is_dir(): config.rmdir()
                elif config.is_symlink(): config.unlink()
                elif config.exists(): config.unlink()
                config.write_bytes(b'fixture-config.json')

    def test_existing_target_is_unchanged(self):
        self.target.mkdir()
        sentinel = self.target / 'keep'
        sentinel.write_text('keep')
        with self.assertRaises(SystemExit): self.prepare()
        self.assertEqual(sentinel.read_text(), 'keep')

    def test_fifo_is_rejected_without_waiting_for_a_writer(self):
        config = self.snapshot / 'config.json'
        config.unlink()
        os.mkfifo(config)
        with self.assertRaises(SystemExit): self.prepare()
        self.assertFalse(self.target.exists())

    def test_modified_safetensors_is_rejected(self):
        model = self.snapshot / 'model.safetensors'
        model.write_bytes(b'x' * self.expected['model.safetensors']['size'])
        with self.assertRaises(SystemExit): self.prepare()
        self.assertFalse(self.target.exists())

    def test_target_inside_git_checkout_is_rejected(self):
        (self.root / '.git').mkdir()
        with self.assertRaises(SystemExit): self.prepare()
        self.assertFalse(self.target.exists())

    def test_failed_context_copy_removes_partial_context(self):
        def fail_copy(source, target, **kwargs):
            target.mkdir(exist_ok=True)
            (target / "partial").write_bytes(b"partial")
            raise OSError('fixture copy failure')
        with patch.object(prepare_model.shutil, 'copytree', fail_copy):
            with self.assertRaises(SystemExit): self.prepare()
        self.assertFalse(self.target.exists())

    def test_download_path_uses_the_same_pins_and_verification(self):
        calls = []
        def download(model, **kwargs):
            calls.append((model, kwargs))
            return str(self.snapshot)
        with patch.dict(sys.modules, {'huggingface_hub': SimpleNamespace(snapshot_download=download)}), \
             patch.object(prepare_model, 'EXPECTED_ARTIFACTS', self.expected):
            prepare_model.main(['--build-context', str(self.target)])
        self.assertEqual(calls, [(prepare_model.MODEL, {
            'revision': prepare_model.REVISION, 'allow_patterns': list(self.expected)})])
        self.assertTrue((self.target / 'model/model-manifest.json').is_file())
