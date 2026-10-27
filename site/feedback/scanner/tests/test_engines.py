import tempfile
import unittest
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'app'))
from engines import ProductionEngines, token_windows, classifier_windows
from scan import ScanFailure


class EngineBoundaryTests(unittest.TestCase):
    def test_classifier_windows_cover_tail_without_truncation(self):
        values=list(range(2049)); windows=list(token_windows(values))
        self.assertTrue(windows)
        self.assertEqual(set(values), {value for window in windows for value in window})
        self.assertTrue(all(len(window)<=510 for window in windows))
        self.assertIn(values[-1],windows[-1])
        self.assertTrue(all(previous[-64:]==following[:64] for previous,following in zip(windows,windows[1:])))
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
            def __call__(self,*args,**kwargs):
                bodies=list(token_windows(list(range(1000))))
                return {'input_ids':[[101]+body+[102] for body in bodies],
                        'special_tokens_mask':[[1]+[0]*len(body)+[1] for body in bodies]}
        class Model:
            config=types.SimpleNamespace(id2label={0:'BENIGN',1:'MALICIOUS'})
            calls=0
            def __call__(self,**kwargs):
                self.calls+=1
                if self.calls==2: raise ScanFailure('classifier_unavailable')
                return types.SimpleNamespace(logits=None)
        fake=types.SimpleNamespace(inference_mode=contextlib.nullcontext,
                                   softmax=lambda *args,**kwargs:[[0.01,0.99]],
                                   tensor=lambda values,**kwargs:values,long='long')
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

class OverflowTokenizerTests(unittest.TestCase):
    class Tokenizer:
        # This double deliberately has no removed prepare_for_model API.
        def __init__(self, ids): self.ids = ids
        def encode(self, text, **kwargs): return self.ids
        def __call__(self, text, **kwargs):
            self.options = kwargs
            windows = []
            start = 0
            while True:
                body = self.ids[start:start + 510]
                windows.append([101] + body + [102])
                if start + 510 >= len(self.ids): break
                start += 446
            return {'input_ids': windows,
                    'attention_mask': [[1] * len(window) for window in windows],
                    'special_tokens_mask': [[1] + [0] * (len(window) - 2) + [1] for window in windows],
                    'overflow_to_sample_mapping': [0] * len(windows)}

    def test_supported_overflow_api_keeps_all_tokens_and_bounds_each_window(self):
        for count in (0, 510, 511, 956, 2049):
            with self.subTest(count=count):
                ids = list(range(1000, 1000 + count))
                tokenizer = self.Tokenizer(ids)
                windows = classifier_windows(tokenizer, 'synthetic')
                self.assertTrue(windows)
                self.assertTrue(all(len(window['input_ids']) <= 512 for window in windows))
                self.assertEqual({token for window in windows for token in window['input_ids'][1:-1]}, set(ids))
                self.assertEqual(tokenizer.options['stride'], 64)
                self.assertTrue(tokenizer.options['return_overflowing_tokens'])
                self.assertTrue(all(set(window) == {'input_ids', 'attention_mask'} for window in windows))
                if ids: self.assertEqual(windows[-1]['input_ids'][-2], ids[-1])

    def test_silent_truncation_or_wrong_overlap_cannot_pass(self):
        from unittest.mock import patch
        tokenizer = self.Tokenizer(list(range(1000, 3049)))
        valid = tokenizer('synthetic')
        for broken in ('tail', 'overlap', 'too-long'):
            import copy
            encoded = copy.deepcopy(valid)
            if broken == 'tail':
                for key in encoded: encoded[key] = encoded[key][:-1]
            elif broken == 'overlap': encoded['input_ids'][1][1] += 1
            else: encoded['input_ids'][0] += [123]
            with self.subTest(broken=broken), patch.object(self.Tokenizer, '__call__', return_value=encoded):
                with self.assertRaises(ScanFailure): classifier_windows(tokenizer, 'synthetic')

    def test_token_limit_fails_before_overflow_inference(self):
        from unittest.mock import patch
        tokenizer = self.Tokenizer(list(range(100001)))
        with patch.object(self.Tokenizer, '__call__') as overflow:
            with self.assertRaises(ScanFailure) as raised:
                classifier_windows(tokenizer, 'synthetic')
            self.assertEqual(raised.exception.reason, 'classifier_input_limit')
            overflow.assert_not_called()
