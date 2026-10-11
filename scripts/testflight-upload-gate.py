"""Avoid archiving stale commits or uploading the same commit on CI retries."""
import json
import os
import subprocess


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True))


def should_upload(repo, sha, run_id, forced=False):
    latest = api(f'repos/{repo}/git/ref/heads/main')['object']['sha']
    if latest != sha:
        return False, 'a newer main commit exists'
    if forced:
        return True, 'explicit manual upload requested'
    runs = api(f'repos/{repo}/actions/workflows/check.yml/runs?head_sha={sha}&branch=main&status=completed&per_page=100')['workflow_runs']
    # Include earlier attempts of this run, not just separate workflow runs.
    candidates = [{'id': run_id}] + [run for run in runs if str(run['id']) != str(run_id)]
    for run in candidates:
        jobs = api(f"repos/{repo}/actions/runs/{run['id']}/jobs?per_page=100&filter=all")['jobs']
        for job in jobs:
            if job['name'] != 'Upload private TestFlight build':
                continue
            if any(step['name'] == 'Sign, archive, and upload to App Store Connect' and
                   step.get('conclusion') == 'success' for step in job.get('steps', [])):
                return False, 'this commit was already uploaded successfully'
    return True, 'latest main commit has not been uploaded'


if __name__ == '__main__':
    allowed, reason = should_upload(os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_SHA'],
                                   os.environ['GITHUB_RUN_ID'], os.environ['GITHUB_EVENT_NAME'] == 'workflow_dispatch')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
        f.write(f'current={str(allowed).lower()}\n')
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
        f.write(('TestFlight allowed: ' if allowed else 'TestFlight skipped: ') + reason + '.\n')
