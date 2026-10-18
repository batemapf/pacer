"""Exercise the native encoded-attachment contract with real JPEGs."""
import base64
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

spec = importlib.util.spec_from_file_location('agent_images', Path(__file__).resolve().parents[1] / 'app-change-agent.py')
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


class FeedbackImageTests(unittest.TestCase):
    def request(self, size=(100, 200), image_format='JPEG'):
        buffer = io.BytesIO()
        Image.new('RGB', size, 'purple').save(buffer, format=image_format)
        raw = buffer.getvalue()
        digest = hashlib.sha256(raw).hexdigest()
        encoded = base64.b64encode(raw).decode()
        # Small chunks deliberately exercise multipart order/retry handling.
        parts = [encoded[i:i + 500] for i in range(0, len(encoded), 500)]
        request_id = '12345678-1234-1234-1234-123456789abc'
        manifest = {'request': request_id, 'images': [{'id': digest, 'parts': len(parts)}]}
        return {
            'body': '<!-- app-change-images:' + json.dumps(manifest) + ' -->',
            'comments': [{'body': f'<!-- app-change-image:{request_id}:{digest}:{i}:{len(parts)} -->\n```base64\n{part}\n```'}
                         for i, part in reversed(list(enumerate(parts)))] + [{'body': 'Please use these colors.'}]
        }

    def test_decodes_real_image_removes_payload_and_preserves_discussion(self):
        request = self.request()
        request['comments'].append(request['comments'][0].copy())  # uncertain POST retry
        with tempfile.TemporaryDirectory() as root:
            paths = agent.prepare_images(request, Path(root))
            self.assertEqual(len(paths), 1)
            with Image.open(paths[0]) as image:
                self.assertEqual(image.size, (100, 200))
                self.assertEqual(image.format, 'JPEG')
            self.assertEqual(request['comments'], [{'body': 'Please use these colors.'}])
            self.assertNotIn('```base64', json.dumps(request))

    def test_incomplete_upload_fails_before_agent(self):
        request = self.request()
        request['comments'].pop(0)
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                agent.prepare_images(request, Path(root))

    def test_conflicting_retry_rejected(self):
        request = self.request()
        duplicate = request['comments'][0].copy()
        duplicate['body'] = duplicate['body'].replace('```base64\n', '```base64\nAAAA')
        request['comments'].append(duplicate)
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(RuntimeError, 'Conflicting'):
                agent.prepare_images(request, Path(root))

    def test_integrity_check_rejects_modified_bytes(self):
        request = self.request()
        comment = request['comments'][-2]
        comment['body'] = comment['body'].replace('```base64\n', '```base64\nAAAA')
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(RuntimeError, 'checksum'):
                agent.prepare_images(request, Path(root))

    def test_non_jpeg_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(RuntimeError, 'JPEG'):
                agent.prepare_images(self.request(image_format='PNG'), Path(root))

    def test_text_only_unchanged(self):
        request = {'body': 'Normal request', 'comments': []}
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(agent.prepare_images(request, Path(root)), [])
            self.assertEqual(request, {'body': 'Normal request', 'comments': []})

    def test_manifest_cannot_supply_a_path(self):
        request = self.request()
        request['body'] = request['body'].replace('"id": "', '"id": "../../')
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(RuntimeError, 'identifier'):
                agent.prepare_images(request, Path(root))
