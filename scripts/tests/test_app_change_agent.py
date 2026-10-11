import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('app_change_agent', Path(__file__).resolve().parents[1] / 'app-change-agent.py')
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


class AgentBoundaryTests(unittest.TestCase):
    def test_protected_files_rejected(self):
        for path in ['.github/workflows/check.yml', 'scripts/publish-testflight.sh',
                     'Pacer/Info.plist', 'Pacer.xcodeproj/project.pbxproj', 'Package.swift',
                     'Sources/PacerCore/../../secrets.swift']:
            self.assertFalse(agent.allowed_path(path), path)

    def test_existing_app_files_allowed(self):
        for path in ['Pacer/ContentView.swift', 'Sources/PacerCore/PaceEngine.swift',
                     'Tests/PacerCoreTests/PaceEngineTests.swift', 'README.md']:
            self.assertTrue(agent.allowed_path(path), path)

    def test_nonmaintainer_cannot_trigger(self):
        with tempfile.TemporaryDirectory() as d:
            event = Path(d) / 'event.json'
            event.write_text('{}')
            with patch.dict(os.environ, GITHUB_EVENT_PATH=str(event), GITHUB_REPOSITORY='owner/repo', GITHUB_ACTOR='outsider'), \
                    patch.object(agent, 'api', return_value={'permission': 'read'}):
                with self.assertRaisesRegex(RuntimeError, 'maintainers'):
                    agent.prepare()

    def test_existing_pr_skips_duplicate(self):
        with tempfile.TemporaryDirectory() as d:
            event = Path(d) / 'event.json'
            event.write_text(json.dumps({'issue': {'number': 42}}))
            issue = {'state': 'open', 'labels': [{'name': 'ready-for-agent'}]}
            with patch.dict(os.environ, GITHUB_EVENT_PATH=str(event), GITHUB_REPOSITORY='owner/repo', GITHUB_ACTOR='owner'), \
                    patch.object(agent, 'api', side_effect=[{'permission': 'admin'}, issue, [{'number': 100}]]), \
                    patch.object(agent, 'output') as output:
                agent.prepare()
                output.assert_called_once_with('run', 'false')

    def test_declined_request_cannot_include_patch(self):
        with tempfile.TemporaryDirectory() as d:
            bundle = Path(d) / 'agent-proposal'
            bundle.mkdir()
            (bundle / 'result.json').write_text('{"status":"declined"}')
            (bundle / 'change.patch').write_text('unexpected change')
            with patch.dict(os.environ, RUNNER_TEMP=d):
                with self.assertRaisesRegex(RuntimeError, 'must not change'):
                    agent.validate()

    def test_prepare_includes_discussion_in_prompt(self):
        with tempfile.TemporaryDirectory() as d:
            event = Path(d) / 'event.json'
            event.write_text(json.dumps({'issue': {'number': 13}}))
            issue = {'state': 'open', 'title': 'Make it colorful', 'body': 'Request',
                     'labels': [{'name': 'ready-for-agent'}]}
            comments = [{'author': 'owner', 'body': 'Use your best judgment man!'}]
            with patch.dict(os.environ, GITHUB_EVENT_PATH=str(event), RUNNER_TEMP=d,
                            GITHUB_REPOSITORY='owner/repo', GITHUB_ACTOR='owner'), \
                    patch.object(agent, 'api', side_effect=[{'permission': 'admin'}, issue, []]), \
                    patch.object(agent, 'issue_comments', return_value=comments), \
                    patch.object(agent, 'command', return_value='a' * 40), \
                    patch.object(agent, 'output'):
                agent.prepare()
            request = json.loads((Path(d) / 'agent-request.json').read_text())
            self.assertEqual(request['comments'], comments)
            self.assertIn('Use your best judgment man!', (Path(d) / 'agent-prompt.txt').read_text())

    def test_comments_are_paginated_and_preserve_order(self):
        def comment(body):
            return {'user': {'login': 'owner'}, 'author_association': 'OWNER',
                    'created_at': '2026-10-11T19:00:00Z', 'body': body}
        with patch.object(agent, 'command', return_value=json.dumps([
                [comment('Question')], [comment('Answer')]])) as command:
            comments = agent.issue_comments('owner/repo', 13)
        self.assertEqual([c['body'] for c in comments], ['Question', 'Answer'])
        self.assertIn('--paginate', command.call_args.args)
        self.assertIn('--slurp', command.call_args.args)

    def test_patch_to_protected_file_is_rejected(self):
        self.apply_patch_fixture('Pacer/Info.plist', rejected=True)

    def test_ordinary_readme_patch_is_accepted(self):
        self.apply_patch_fixture('README.md', rejected=False)

    def apply_patch_fixture(self, name, rejected):
        old_cwd = os.getcwd()
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            os.chdir(root)
            try:
                subprocess.run(['git', 'init', '-q'], check=True)
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('original\n')
                subprocess.run(['git', 'add', '.'], check=True)
                subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture'], check=True)
                base = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
                path.write_text('changed\n')
                delta = subprocess.check_output(['git', 'diff', '--binary'])
                subprocess.run(['git', 'checkout', '--', name], check=True)
                bundle = root / 'proposal'
                bundle.mkdir()
                (bundle / 'base.txt').write_text(base)
                (bundle / 'change.patch').write_bytes(delta)
                if rejected:
                    with self.assertRaisesRegex(RuntimeError, 'scope'):
                        agent.apply_proposal(bundle)
                else:
                    self.assertEqual(agent.apply_proposal(bundle), ['README.md'])
            finally:
                os.chdir(old_cwd)
