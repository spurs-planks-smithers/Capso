import tempfile
import unittest
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'app'))
from engines import ProductionEngines, token_windows
from scan import ScanFailure


class EngineBoundaryTests(unittest.TestCase):
    def test_classifier_windows_cover_tail_without_truncation(self):
        values=list(range(2049)); windows=list(token_windows(values))
        self.assertTrue(windows)
        self.assertEqual(set(values), {value for window in windows for value in window})
        self.assertTrue(all(len(window)<=510 for window in windows))
        self.assertIn(values[-1],windows[-1])
    def test_empty_text_still_has_a_classifier_window(self):
        self.assertEqual(list(token_windows([])),[[]])
    def test_stale_definitions_fail_before_any_download(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ScanFailure) as raised:
                ProductionEngines(definitions_dir=folder).prepare_definitions({'updatedAt':'2020-01-01T00:00:00Z','files':[]})
            self.assertEqual(raised.exception.reason,'stale_signatures')
    def test_missing_model_never_fetches_a_remote_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ScanFailure) as raised:
                ProductionEngines(model_dir=folder).prepare_classifier()
            self.assertEqual(raised.exception.reason,'classifier_unavailable')

class ClassifierCompletionTests(unittest.TestCase):
    def test_positive_window_does_not_hide_a_later_engine_failure(self):
        import contextlib
        import types
        from unittest.mock import patch
        class Tokenizer:
            def encode(self,*args,**kwargs): return list(range(1000))
            def prepare_for_model(self,*args,**kwargs):
                return {'input_ids':types.SimpleNamespace(shape=(1,512))}
        class Model:
            config=types.SimpleNamespace(id2label={0:'BENIGN',1:'MALICIOUS'})
            calls=0
            def __call__(self,**kwargs):
                self.calls+=1
                if self.calls==2: raise ScanFailure('classifier_unavailable')
                return types.SimpleNamespace(logits=None)
        fake=types.SimpleNamespace(inference_mode=contextlib.nullcontext,
                                   softmax=lambda *args,**kwargs:[[0.01,0.99]])
        engine=ProductionEngines(); engine.tokenizer=Tokenizer(); engine.model=Model()
        with patch.dict(sys.modules,{'torch':fake}), self.assertRaises(ScanFailure) as raised:
            engine.classify('A bounded document with several windows.')
        self.assertEqual(raised.exception.reason,'classifier_unavailable')
        self.assertEqual(engine.model.calls,2)

class AntivirusBatchTests(unittest.TestCase):
    def batch(self,stdout_for,returncode=0,payloads=None):
        import types
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder:
            def run(args,**kwargs):
                paths=[Path(value) for value in args if '/input-' in str(value)]
                self.assertTrue(paths)
                self.assertTrue(all(path.is_relative_to(Path(folder)) for path in paths))
                return types.SimpleNamespace(returncode=returncode,stdout=stdout_for(paths),stderr=b'')
            with patch('engines.command',run):
                ProductionEngines(temporary_root=folder).malware_many(payloads if payloads is not None else [b'first',b'last'])
    def test_batch_requires_each_completed_file_status(self):
        self.batch(lambda paths:b''.join(str(path).encode()+b': OK\n' for path in paths))
    def test_missing_last_status_cannot_pass(self):
        with self.assertRaises(ScanFailure) as raised:
            self.batch(lambda paths:str(paths[0]).encode()+b': OK\n')
        self.assertEqual(raised.exception.reason,'malware_scan_incomplete')
    def test_bad_last_member_cannot_pass_after_first_ok(self):
        with self.assertRaises(ScanFailure) as raised:
            self.batch(lambda paths:str(paths[0]).encode()+b': OK\n'+str(paths[-1]).encode()+b': Eicar-Test-Signature FOUND\n',1)
        self.assertEqual(raised.exception.reason,'malware_detected')
    def test_empty_batch_is_not_a_completed_scan(self):
        with self.assertRaises(ScanFailure): self.batch(lambda paths:b'',payloads=[])
