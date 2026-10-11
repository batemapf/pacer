"""Upload the exported IPA and require explicit acknowledgement from Apple."""
import json
import os
from pathlib import Path
import subprocess
import sys


def upload(export_directory):
    ipas = sorted(Path(export_directory).glob('*.ipa'))
    if len(ipas) != 1 or not ipas[0].is_file() or ipas[0].stat().st_size == 0:
        raise RuntimeError('Expected exactly one nonempty exported IPA.')
    result = subprocess.run([
        'xcrun', 'altool', '--upload-app', '--type', 'ios', '--file', str(ipas[0]),
        '--apiKey', os.environ['ASC_API_KEY_ID'],
        '--apiIssuer', os.environ['ASC_API_ISSUER_ID'], '--output-format', 'json',
    ], capture_output=True, text=True)
    # Apple sometimes reports an upload error with a zero process exit status.
    # Require its structured success acknowledgement before writing the summary.
    if result.stdout:
        print(result.stdout, flush=True)
    if result.stderr:
        print(result.stderr, file=sys.stderr, flush=True)
    if result.returncode:
        raise RuntimeError('App Store Connect upload command failed.')
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError('Upload returned no valid JSON acknowledgement.') from error
    if not isinstance(response, dict) or response.get('product-errors') or not response.get('success-message'):
        raise RuntimeError('Apple did not acknowledge a successful upload.')


if __name__ == '__main__':
    try:
        upload(sys.argv[1])
    except (RuntimeError, OSError, KeyError) as error:
        print(f'::error::{error}', file=sys.stderr)
        sys.exit(1)
