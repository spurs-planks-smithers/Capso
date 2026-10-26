import io
import json
import multiprocessing.connection
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
import sys
sys.path.insert(0,str(Path(__file__).parents[1]/'app'))
import server
from engines import ProductionEngines


def leaking_child(connection,job):
    folder=Path(tempfile.mkdtemp(prefix='av-',dir=os.environ['TMPDIR']))
    file=folder/'input'; file.write_bytes(b'private original bytes')
    Path(job['tracking']).write_text(str(file))
    time.sleep(30)


def later_child(connection,job):
    connection.send_bytes(json.dumps({'version':1,'status':'passed',
        'previousFileExists':Path(job['previous']).exists()}).encode())
    connection.close()
    time.sleep(1)


class RuntimeCleanupTests(unittest.TestCase):
    def setUp(self):
        self.previous_cleanup_state=server.CLEANUP_FAILED
        server.CLEANUP_FAILED=False
    def tearDown(self): server.CLEANUP_FAILED=self.previous_cleanup_state

    def test_timeout_removes_original_before_a_later_job(self):
        original_poll=multiprocessing.connection.Connection.poll
        with tempfile.TemporaryDirectory() as folder:
            parent=Path(folder); tracking=parent/'tracking'
            with patch.dict(os.environ,{'TMPDIR':folder}), patch.object(server,'JOB_PARENT',folder,create=True), \
                 patch.object(server,'child',leaking_child), \
                 patch.object(multiprocessing.connection.Connection,'poll',lambda self,timeout=0: original_poll(self,min(timeout,0.4))):
                result=server.run_job({'tracking':str(tracking)})
            self.assertEqual(result['status'],'held')
            self.assertIn('scanner_timeout',result['reasonCodes'])
            self.assertTrue(tracking.is_file())
            original=Path(tracking.read_text())
            self.assertFalse(original.exists(),'A timed-out job left original bytes on disk.')
            self.assertFalse(original.parent.exists(),'The private job folder survives its timeout.')
            with patch.object(server,'JOB_PARENT',folder,create=True), patch.object(server,'child',later_child):
                later=server.run_job({'previous':str(original)})
            self.assertFalse(later['previousFileExists'])

    def test_antivirus_private_files_stay_in_job_directory(self):
        from types import SimpleNamespace
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            def scanned(args,**kwargs):
                target=Path(args[-1])
                self.assertTrue(target.is_relative_to(root))
                self.assertEqual(target.read_bytes(),b'private original bytes')
                self.assertEqual(Path(kwargs['temporary_root']),root)
                return SimpleNamespace(returncode=0,stdout=str(target).encode()+b': OK\n',stderr=b'')
            with patch('engines.command',scanned):
                ProductionEngines(temporary_root=root).malware(b'private original bytes')
            self.assertEqual(list(root.iterdir()),[])

    def test_cleanup_failure_holds_result_and_disables_later_jobs(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(server,'JOB_PARENT',folder), patch.object(server,'child',later_child), \
                 patch.object(server.shutil,'rmtree',side_effect=OSError('synthetic cleanup failure')):
                result=server.run_job({'previous':folder+'/missing'})
            self.assertEqual(result['status'],'held')
            self.assertIn('scanner_cleanup_failed',result['reasonCodes'])
            with patch.object(server,'child') as later:
                self.assertEqual(server.run_job({})['reasonCodes'],['scanner_cleanup_failed'])
                later.assert_not_called()
