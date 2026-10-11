import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('upload_gate', Path(__file__).resolve().parents[1] / 'testflight-upload-gate.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class UploadGateTests(unittest.TestCase):
    def test_stale_commit_skips_archive(self):
        with patch.object(gate, 'api', return_value={'object': {'sha': 'new'}}):
            self.assertFalse(gate.should_upload('owner/repo', 'old', 42)[0])

    def test_retry_of_uploaded_commit_skips(self):
        replies = [{'object': {'sha': 'same'}}, {'workflow_runs': [{'id': 41}]}, {'jobs': []},
                   {'jobs': [{'name': 'Upload private TestFlight build', 'steps': [
                       {'name': 'Sign, archive, and upload to App Store Connect', 'conclusion': 'success'}]}]}]
        with patch.object(gate, 'api', side_effect=replies):
            self.assertFalse(gate.should_upload('owner/repo', 'same', 42)[0])

    def test_failed_or_skipped_upload_can_retry(self):
        for conclusion in ['failure', 'skipped', 'cancelled']:
            replies = [{'object': {'sha': 'same'}}, {'workflow_runs': [{'id': 41}]}, {'jobs': []},
                       {'jobs': [{'name': 'Upload private TestFlight build', 'steps': [
                           {'name': 'Sign, archive, and upload to App Store Connect', 'conclusion': conclusion}]}]}]
            with patch.object(gate, 'api', side_effect=replies):
                self.assertTrue(gate.should_upload('owner/repo', 'same', 42)[0])

    def test_new_commit_uploads(self):
        with patch.object(gate, 'api', side_effect=[{'object': {'sha': 'new'}}, {'workflow_runs': []}, {'jobs': []}]):
            self.assertTrue(gate.should_upload('owner/repo', 'new', 42)[0])

    def test_manual_force_can_replace_build(self):
        with patch.object(gate, 'api', return_value={'object': {'sha': 'same'}}) as api:
            self.assertTrue(gate.should_upload('owner/repo', 'same', 42, forced=True)[0])
            self.assertEqual(api.call_count, 1)

    def test_earlier_successful_attempt_of_same_run_skips(self):
        replies = [{'object': {'sha': 'same'}}, {'workflow_runs': []},
                   {'jobs': [{'name': 'Upload private TestFlight build', 'steps': [
                       {'name': 'Sign, archive, and upload to App Store Connect', 'conclusion': 'success'}]}]}]
        with patch.object(gate, 'api', side_effect=replies):
            self.assertFalse(gate.should_upload('owner/repo', 'same', 42)[0])
