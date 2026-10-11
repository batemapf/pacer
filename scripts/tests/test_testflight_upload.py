"""Verify renamed IPA discovery and reject false-positive upload results."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('upload_testflight', Path(__file__).resolve().parents[1] / 'upload-testflight.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UploadTests(unittest.TestCase):
    def perform_upload(self, response, names=('Speed Up or Slow Down.ipa',), code=0):
        with tempfile.TemporaryDirectory() as directory:
            for name in names:
                (Path(directory) / name).write_bytes(b'synthetic IPA')
            with patch.dict(os.environ, ASC_API_KEY_ID='TEST', ASC_API_ISSUER_ID='TEST'), \
                    patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], code, response, '')) as run:
                module.upload(directory)
                return run.call_args.args[0]

    def test_renamed_ipa_uploads(self):
        command = self.perform_upload('{"success-message":"No errors uploading archive."}')
        self.assertTrue(command[command.index('--file') + 1].endswith('/Speed Up or Slow Down.ipa'))

    def test_zero_exit_with_apple_error_fails(self):
        with self.assertRaises(RuntimeError):
            self.perform_upload('{"product-errors":[{"message":"File does not exist"}]}')

    def test_missing_ipa_fails(self):
        with self.assertRaises(RuntimeError):
            self.perform_upload('{}', names=())

    def test_multiple_ipas_fail(self):
        with self.assertRaises(RuntimeError):
            self.perform_upload('{}', names=('One.ipa', 'Two.ipa'))

    def test_no_acknowledgement_fails(self):
        with self.assertRaises(RuntimeError):
            self.perform_upload('{}')

    def test_nonzero_exit_fails(self):
        with self.assertRaises(RuntimeError):
            self.perform_upload('{"success-message":"uploaded"}', code=1)
