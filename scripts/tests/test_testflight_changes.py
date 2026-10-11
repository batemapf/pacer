import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('testflight_changes', Path(__file__).resolve().parents[1] / 'testflight-changes.py')
changes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(changes)


class ReleaseChangeTests(unittest.TestCase):
    event = {'before': 'a' * 40, 'after': 'b' * 40}

    def test_documentation_and_agent_automation_do_not_upload(self):
        with patch.object(changes.subprocess, 'check_output', return_value=b'README.md\0APP-CHANGE-AGENT.md\0.github/workflows/app-change.yml\0scripts/app-change-agent.py\0'):
            self.assertFalse(changes.release_needed('push', self.event))

    def test_app_change_among_documentation_uploads(self):
        with patch.object(changes.subprocess, 'check_output', return_value=b'README.md\0Pacer/ContentView.swift\0'):
            self.assertTrue(changes.release_needed('push', self.event))

    def test_assets_project_and_app_inputs_upload(self):
        for path in ['Pacer/Assets.xcassets/AppIcon.appiconset/AppIcon.png',
                     'Pacer.xcodeproj/project.pbxproj', 'Sources/PacerCore/PaceEngine.swift',
                     'Package.swift']:
            self.assertTrue(changes.affects_release(path), path)

    def test_test_only_changes_do_not_upload(self):
        self.assertFalse(changes.affects_release('Tests/PacerCoreTests/PaceEngineTests.swift'))

    def test_release_automation_alone_does_not_upload(self):
        for path in ['scripts/upload-testflight.py', 'scripts/publish-testflight.sh',
                     'scripts/testflight-changes.py', '.github/workflows/check.yml']:
            self.assertFalse(changes.affects_release(path), path)

    def test_manual_validation_does_not_upload_by_default(self):
        self.assertFalse(changes.release_needed('workflow_dispatch', {}))
        self.assertFalse(changes.release_needed('workflow_dispatch', {'inputs': {'upload_testflight': 'false'}}))

    def test_explicit_manual_upload_remains_available(self):
        self.assertTrue(changes.release_needed('workflow_dispatch', {'inputs': {'upload_testflight': 'true'}}))
        self.assertTrue(changes.release_needed('workflow_dispatch', {'inputs': {'upload_testflight': True}}))

    def test_first_push_uploads_conservatively(self):
        self.assertTrue(changes.release_needed('push', {'before': '0' * 40, 'after': 'b' * 40}))

    def test_whole_push_range_and_deletions_are_compared(self):
        with patch.object(changes.subprocess, 'check_output', return_value=b'Pacer/RunTracker.swift\0') as diff:
            self.assertTrue(changes.release_needed('push', self.event))
            self.assertEqual(diff.call_args.args[0], ['git', 'diff', '--name-only', '--no-renames', '-z', 'a' * 40, 'b' * 40, '--'])
