"""Exercise CI profile validation with synthetic assets; never needs real credentials."""
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'publish-testflight.sh'
VALIDATE = re.findall(r"python3 - <<'PY'\n(.*?)\nPY", SCRIPT.read_text(), re.S)[1]


class ProfileValidationTests(unittest.TestCase):
    def run_profile(self, changes=None, identity=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Pacer').mkdir()
            (root / 'Pacer/Info.plist').write_bytes(plistlib.dumps({'CFBundleVersion': '1'}))
            certificate = b'synthetic certificate fixture, not a signing asset'
            fingerprint = hashlib.sha1(certificate).hexdigest().upper()
            profile = {
                'UUID': '11111111-2222-3333-4444-555555555555',
                'TeamIdentifier': ['ABCDEF1234'],
                'ApplicationIdentifierPrefix': ['ABCDEF1234'],
                'Entitlements': {
                    'com.apple.developer.team-identifier': 'ABCDEF1234',
                    'application-identifier': 'ABCDEF1234.com.example.pacer',
                    'get-task-allow': False,
                },
                'ExpirationDate': datetime.datetime(2099, 1, 1),
                'DeveloperCertificates': [certificate],
            }
            if changes:
                changes(profile)
            (root / 'profile.plist').write_bytes(plistlib.dumps(profile))
            (root / 'identities.txt').write_text(fingerprint if identity else '')
            env = dict(os.environ, PACER_SIGNING_DIR=str(root), IOS_TEAM_ID='ABCDEF1234',
                       IOS_BUNDLE_ID='com.example.pacer', GITHUB_RUN_NUMBER='42', GITHUB_RUN_ATTEMPT='2',
                       APP_CHANGE_GH_TOKEN='synthetic-issue-only-token')
            result = subprocess.run(['python3', '-c', VALIDATE], cwd=root, env=env,
                                    capture_output=True, text=True)
            if result.returncode == 0:
                exported = plistlib.loads((root / 'ExportOptions.plist').read_bytes())
                info = plistlib.loads((root / 'Pacer/Info.plist').read_bytes())
                self.assertEqual(exported['signingCertificate'], fingerprint)
                self.assertEqual(exported['provisioningProfiles']['com.example.pacer'], profile['UUID'])
                self.assertEqual(info['CFBundleVersion'], '42.2')
                self.assertEqual(info['AppChangeGitHubToken'], 'synthetic-issue-only-token')
            return result

    def test_matching_profile_exports_manual_signing_and_unique_build(self):
        self.assertEqual(self.run_profile().returncode, 0)

    def test_wrong_team_is_rejected(self):
        r = self.run_profile(lambda p: p.update(TeamIdentifier=['OTHERTEAM1']))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('IOS_TEAM_ID', r.stderr)

    def test_wrong_bundle_is_rejected(self):
        r = self.run_profile(lambda p: p['Entitlements'].update({'application-identifier': 'ABCDEF1234.com.other.app'}))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('IOS_BUNDLE_ID', r.stderr)

    def test_expired_profile_is_rejected(self):
        r = self.run_profile(lambda p: p.update(ExpirationDate=datetime.datetime(2000, 1, 1)))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('expired', r.stderr)

    def test_ad_hoc_profile_is_rejected(self):
        r = self.run_profile(lambda p: p.update(ProvisionedDevices=['test-device']))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('App Store Connect distribution', r.stderr)

    def test_missing_matching_private_key_is_rejected(self):
        r = self.run_profile(identity=False)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('certificate/private-key', r.stderr)


if __name__ == '__main__':
    unittest.main()
