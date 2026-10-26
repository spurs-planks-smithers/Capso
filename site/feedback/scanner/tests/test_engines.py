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
