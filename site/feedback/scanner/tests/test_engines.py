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
