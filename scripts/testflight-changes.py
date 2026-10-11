"""Decide release eligibility without suppressing normal CI checks."""
import json
import os
from pathlib import Path
import re
import subprocess


def affects_release(path):
    return path.startswith(('Pacer/', 'Sources/', 'Pacer.xcodeproj/')) or path in {
        'Package.swift', 'Package.resolved',
        '.github/workflows/check.yml',
        'scripts/publish-testflight.sh', 'scripts/upload-testflight.py',
        'scripts/testflight-changes.py',
    }


def release_needed(event_name, event):
    # Manual runs remain an explicit way to upload a replacement build.
    if event_name == 'workflow_dispatch':
        return True
    if event_name != 'push':
        return False
    before, after = event.get('before', ''), event.get('after', '')
    if not all(re.fullmatch(r'[a-f0-9]{40}', sha) for sha in (before, after)) or before == '0' * 40:
        print('::warning::No usable previous commit; allowing upload conservatively.')
        return True
    try:
        paths = subprocess.check_output([
            'git', 'diff', '--name-only', '--no-renames', '-z', before, after, '--'
        ]).decode().split('\0')
    except subprocess.CalledProcessError:
        print('::warning::Unable to compare push commits; allowing upload conservatively.')
        return True
    return any(affects_release(path) for path in paths if path)


if __name__ == '__main__':
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    needed = release_needed(os.environ['GITHUB_EVENT_NAME'], event)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
        f.write(f'needed={str(needed).lower()}\n')
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
        f.write('TestFlight: ' + ('upload eligible after checks pass.' if needed else 'skipped; no app or release changes.') + '\n')
