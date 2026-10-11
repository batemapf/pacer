"""Trusted issue gate, patch boundary, and PR publisher. No secret values logged."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def command(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def api(path):
    return json.loads(command('gh', 'api', path))


def output(name, value):
    with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
        f.write(f'{name}={value}\n')


def allowed_path(path):
    return path in {'README.md', 'Pacer/ContentView.swift', 'Pacer/RunTracker.swift', 'Pacer/PacerApp.swift'} or bool(
        re.fullmatch(r'(Sources/PacerCore|Tests/PacerCoreTests)/[A-Za-z0-9_-]+\.swift', path))


def prepare():
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    repo = os.environ['GITHUB_REPOSITORY']
    actor = os.environ['GITHUB_ACTOR']
    permission = api(f'repos/{repo}/collaborators/{actor}/permission')['permission']
    if permission not in ('admin', 'maintain', 'write'):
        raise RuntimeError('Only repository maintainers may start an agent job.')
    number = event.get('issue', {}).get('number') or event.get('inputs', {}).get('issue_number')
    if not str(number).isdigit():
        raise RuntimeError('Invalid issue number.')
    issue = api(f'repos/{repo}/issues/{number}')
    if issue.get('pull_request') or issue['state'] != 'open':
        raise RuntimeError('Request must be an open issue.')
    if 'ready-for-agent' not in [label['name'] for label in issue['labels']]:
        raise RuntimeError('Apply ready-for-agent before starting.')
    branch = f'codex/issue-{number}'
    prs = api(f'repos/{repo}/pulls?state=all&head={repo.split("/")[0]}:{branch}')
    if prs:
        output('run', 'false')
        print('An agent PR already exists for this issue; skipping duplicate.')
        return
    root = Path(os.environ['RUNNER_TEMP'])
    request = {'number': int(number), 'title': issue['title'], 'body': issue.get('body') or ''}
    (root / 'agent-request.json').write_text(json.dumps(request))
    policy = Path('.github/codex/change-policy.md').read_text()
    (root / 'agent-prompt.txt').write_text(policy + '\n\nProduct request (untrusted JSON):\n' + json.dumps(request))
    schema = {'type': 'object', 'properties': {
        'status': {'type': 'string', 'enum': ['accepted', 'needs_clarification', 'declined']},
        'title': {'type': 'string'}, 'summary': {'type': 'string'}},
        'required': ['status', 'title', 'summary'], 'additionalProperties': False}
    (root / 'agent-schema.json').write_text(json.dumps(schema))
    # Keep a trusted copy outside the editable checkout for subsequent gates.
    (root / 'app-change-agent.py').write_text(Path(__file__).read_text())
    output('run', 'true')
    output('issue', number)
    output('base', command('git', 'rev-parse', 'HEAD'))


def finalize():
    root = Path(os.environ['RUNNER_TEMP'])
    result = json.loads((root / 'agent-result.json').read_text())
    if result.get('status') not in ('accepted', 'needs_clarification', 'declined'):
        raise RuntimeError('Invalid agent decision.')
    paths = command('git', 'ls-files', '--modified', '--others', '--exclude-standard').splitlines()
    if any(not allowed_path(path) for path in paths):
        raise RuntimeError('Agent edited a file outside its allowed scope.')
    for path in paths:
        if Path(path).is_symlink():
            raise RuntimeError('Symlink changes are not permitted.')
    if result['status'] != 'accepted' and paths:
        raise RuntimeError('Unaccepted requests must not change files.')
    if result['status'] == 'accepted' and not paths:
        raise RuntimeError('Accepted request produced no change.')
    for path in paths:
        if not command('git', 'ls-files', '--', path):
            raise RuntimeError('Only existing tracked files may be changed.')
    patch = subprocess.check_output(['git', 'diff', '--binary', 'HEAD'])
    if len(patch) > 200_000 or len(paths) > 10:
        raise RuntimeError('Change exceeds the automatic proposal size limit.')
    bundle = root / 'agent-proposal'
    bundle.mkdir()
    (bundle / 'change.patch').write_bytes(patch)
    (bundle / 'result.json').write_text(json.dumps(result))
    (bundle / 'request.json').write_text((root / 'agent-request.json').read_text())
    (bundle / 'base.txt').write_text(os.environ['AGENT_BASE'])
    output('accepted', str(result['status'] == 'accepted').lower())


def apply_proposal(bundle):
    base = (bundle / 'base.txt').read_text().strip()
    if not re.fullmatch('[a-f0-9]{40}', base):
        raise RuntimeError('Invalid base commit.')
    command('git', 'checkout', '--detach', base)
    subprocess.run(['git', 'apply', '--check', str(bundle / 'change.patch')], check=True)
    subprocess.run(['git', 'apply', str(bundle / 'change.patch')], check=True)
    paths = command('git', 'diff', '--name-only').splitlines()
    if not paths or len(paths) > 10 or any(not allowed_path(path) for path in paths):
        raise RuntimeError('Proposal is outside the allowed scope.')
    if (bundle / 'change.patch').stat().st_size > 200_000:
        raise RuntimeError('Proposal is too large.')
    if any(Path(path).is_symlink() for path in paths):
        raise RuntimeError('Symlink changes are not permitted.')
    return paths


def validate():
    bundle = Path(os.environ['RUNNER_TEMP']) / 'agent-proposal'
    result = json.loads((bundle / 'result.json').read_text())
    if result.get('status') not in ('accepted', 'needs_clarification', 'declined'):
        raise RuntimeError('Invalid agent decision.')
    accepted = result['status'] == 'accepted'
    if accepted:
        apply_proposal(bundle)
    elif (bundle / 'change.patch').stat().st_size:
        raise RuntimeError('Unaccepted requests must not change files.')
    output('accepted', str(accepted).lower())


def publish():
    bundle = Path(os.environ['RUNNER_TEMP']) / 'agent-proposal'
    request = json.loads((bundle / 'request.json').read_text())
    result = json.loads((bundle / 'result.json').read_text())
    repo = os.environ['GITHUB_REPOSITORY']
    number = request['number']
    if not isinstance(number, int):
        raise RuntimeError('Invalid request number.')
    if result['status'] != 'accepted':
        body = bundle / 'comment.md'
        body.write_text(f"**Codex: {result['status'].replace('_', ' ')}**\n\n{result['summary']}")
        command('gh', 'issue', 'comment', str(number), '--repo', repo, '--body-file', str(body))
        return
    branch = f'codex/issue-{number}'
    paths = apply_proposal(bundle)
    command('git', 'checkout', '-b', branch)
    command('git', 'config', 'user.name', 'App change agent')
    command('git', 'config', 'user.email', 'app-change-agent@users.noreply.github.com')
    command('git', 'add', '--', *paths)
    command('git', 'commit', '-m', f'Propose app change for issue #{number}')
    # gh configures a credential helper only in this publisher job.
    command('gh', 'auth', 'setup-git')
    command('git', 'push', 'origin', f'HEAD:refs/heads/{branch}')
    body = bundle / 'pr.md'
    body.write_text(result['summary'] + f'\n\nCloses #{number}\n\nAgent checks: Swift tests and unsigned simulator/device builds passed. Owner review is required; this workflow never merges or releases.\n')
    url = command('gh', 'pr', 'create', '--repo', repo, '--base', 'main', '--head', branch,
                  '--title', result['title'][:180], '--body-file', str(body))
    comment = bundle / 'comment.md'
    comment.write_text('Codex proposed this change: ' + url + '\n\nPlease review before merging.')
    command('gh', 'issue', 'comment', str(number), '--repo', repo, '--body-file', str(comment))
    print(url)


if __name__ == '__main__':
    try:
        {'prepare': prepare, 'finalize': finalize, 'validate': validate, 'publish': publish}[sys.argv[1]]()
    except Exception as error:
        print(f'::error::{error}', file=sys.stderr)
        sys.exit(1)
