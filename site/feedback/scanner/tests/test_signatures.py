import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('signature_updater',Path(__file__).parents[1]/'update_signatures.py')
updater=importlib.util.module_from_spec(spec); spec.loader.exec_module(updater)


class SignatureSeedTests(unittest.TestCase):
    def test_seed_verifies_every_database_before_copying(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); source=root/'seed'; target=root/'new'; source.mkdir(); target.mkdir()
            for name in updater.NAMES: (source/name).write_bytes(name.encode())
            checked=[]
            def verify(file):
                self.assertEqual(list(target.iterdir()),[])
                checked.append(file.name)
            with patch.object(updater,'verify_database',verify): updater.prepare_seed(source,target)
            self.assertEqual(checked,list(updater.NAMES))
            self.assertEqual({file.name:file.read_bytes() for file in target.iterdir()},
                             {name:name.encode() for name in updater.NAMES})
    def test_invalid_seed_copies_nothing(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); source=root/'seed'; target=root/'new'; source.mkdir(); target.mkdir()
            with self.assertRaises(SystemExit): updater.prepare_seed(source,target)
            self.assertEqual(list(target.iterdir()),[])
