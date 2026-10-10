#!/usr/bin/env python3
"""Create non-secret CI placeholders using an administrator's authenticated gh CLI.

Preserves existing variables and environment settings. Does not create fake secrets.
"""
import json
import subprocess

REPO = 'batemapf/pacer'
BASE = 'repos/' + REPO
ENVIRONMENT = BASE + '/environments/testflight'


def api(path, method='GET', data=None, missing_ok=False):
    cmd = ['gh', 'api', '--method', method, path]
    if data is not None:
        cmd += ['--input', '-']
    result = subprocess.run(cmd, input=None if data is None else json.dumps(data),
                            text=True, capture_output=True)
    if result.returncode:
        if missing_ok and 'HTTP 404' in result.stderr:
            return None
        raise SystemExit(result.stderr.strip() or 'GitHub configuration request failed.')
    return json.loads(result.stdout) if result.stdout.strip() else {}


def variable(base, name, value):
    if api(base + '/variables/' + name, missing_ok=True) is not None:
        print('Preserved existing variable: ' + name)
        return
    api(base + '/variables', 'POST', {'name': name, 'value': value})
    print('Created placeholder: ' + name)


def main():
    existing = api(ENVIRONMENT, missing_ok=True)
    if existing is None:
        api(ENVIRONMENT, 'PUT', {
            'deployment_branch_policy': {'protected_branches': False, 'custom_branch_policies': True}
        })
        api(ENVIRONMENT + '/deployment-branch-policies', 'POST', {'name': 'main', 'type': 'branch'})
        print('Created testflight environment with main-only deployments.')
    else:
        print('Preserved existing testflight environment; check its branch restrictions in Settings.')
    variable(BASE + '/actions', 'TESTFLIGHT_ENABLED', 'false')
    for name in ['IOS_TEAM_ID', 'IOS_BUNDLE_ID', 'ASC_API_KEY_ID', 'ASC_API_ISSUER_ID']:
        variable(ENVIRONMENT, name, 'SET_ME')
    print('No secrets were created. Complete TESTFLIGHT-CI.md before enabling uploads.')


if __name__ == '__main__':
    main()
