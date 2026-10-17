#!/usr/bin/env bash
# Runs only on an ephemeral GitHub macOS runner. Never enable shell tracing.
set -euo pipefail
umask 077

for name in IOS_TEAM_ID IOS_BUNDLE_ID ASC_API_KEY_ID ASC_API_ISSUER_ID \
    IOS_DISTRIBUTION_P12_BASE64 IOS_DISTRIBUTION_P12_PASSWORD \
    IOS_APP_STORE_PROFILE_BASE64 IOS_WIDGET_APP_STORE_PROFILE_BASE64 ASC_API_KEY_P8_BASE64 APP_CHANGE_GH_TOKEN; do
    value="${!name:-}"
    if [[ -z "$value" || "$value" == SET_ME* ]]; then
        echo "::error::Missing configuration: $name. Follow TESTFLIGHT-CI.md."
        exit 1
    fi
done
if [[ "${RUNNER_OS:-}" != macOS || -z "${RUNNER_TEMP:-}" ]]; then
    echo '::error::This script requires a GitHub-hosted macOS runner.'
    exit 1
fi

signing_dir="$(mktemp -d "$RUNNER_TEMP/pacer-signing.XXXXXX")"
keychain="$signing_dir/signing.keychain-db"
installed_profile=""
installed_widget_profile=""
cleanup() {
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    if [[ -n "$installed_profile" ]]; then rm -f "$installed_profile"; fi
    if [[ -n "$installed_widget_profile" ]]; then rm -f "$installed_widget_profile"; fi
    rm -rf "$signing_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export PACER_SIGNING_DIR="$signing_dir"

python3 - <<'PY'
import base64, os, re
from pathlib import Path
root = Path(os.environ['PACER_SIGNING_DIR'])
if not re.fullmatch(r'[A-Z0-9]{10}', os.environ['IOS_TEAM_ID']):
    raise SystemExit('IOS_TEAM_ID must be the paid Apple team ID (10 characters).')
if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', os.environ['IOS_BUNDLE_ID']):
    raise SystemExit('IOS_BUNDLE_ID must be the exact explicit app bundle identifier.')
if not re.fullmatch(r'[A-Z0-9]+', os.environ['ASC_API_KEY_ID']):
    raise SystemExit('Invalid ASC_API_KEY_ID.')
import uuid
try: uuid.UUID(os.environ['ASC_API_ISSUER_ID'])
except ValueError: raise SystemExit('ASC_API_ISSUER_ID must be the team API issuer UUID.')
(root / 'private_keys').mkdir()
files = {
    'IOS_DISTRIBUTION_P12_BASE64': root / 'distribution.p12',
    'IOS_APP_STORE_PROFILE_BASE64': root / 'app.mobileprovision',
    'IOS_WIDGET_APP_STORE_PROFILE_BASE64': root / 'widget.mobileprovision',
    'ASC_API_KEY_P8_BASE64': root / 'private_keys' / ('AuthKey_' + os.environ['ASC_API_KEY_ID'] + '.p8'),
}
for name, path in files.items():
    try:
        raw = base64.b64decode(''.join(os.environ[name].split()), validate=True)
        if not raw: raise ValueError()
    except (ValueError, base64.binascii.Error):
        raise SystemExit('Invalid base64 secret: ' + name)
    path.write_bytes(raw)
PY

keychain_password="$(openssl rand -hex 32)"
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$signing_dir/distribution.p12" -P "$IOS_DISTRIBUTION_P12_PASSWORD" \
    -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
security cms -D -i "$signing_dir/app.mobileprovision" > "$signing_dir/profile.plist"
security cms -D -i "$signing_dir/widget.mobileprovision" > "$signing_dir/widget-profile.plist"
security find-identity -v -p codesigning "$keychain" > "$signing_dir/identities.txt"

python3 - <<'PY'
import datetime, hashlib, os, plistlib, re
from pathlib import Path
root = Path(os.environ['PACER_SIGNING_DIR'])
team = os.environ['IOS_TEAM_ID']
bundle = os.environ['IOS_BUNDLE_ID']
identities = (root / 'identities.txt').read_text()
valid = set(re.findall(r'\b[0-9A-F]{40}\b', identities))

def validate_profile(filename, expected_bundle):
    p = plistlib.loads((root / filename).read_bytes())
    e = p.get('Entitlements', {})
    if team not in p.get('TeamIdentifier', []) or e.get('com.apple.developer.team-identifier') != team:
        raise SystemExit(filename + ': Provisioning profile does not match IOS_TEAM_ID.')
    prefixes = p.get('ApplicationIdentifierPrefix', [])
    if e.get('application-identifier') not in [prefix + '.' + expected_bundle for prefix in prefixes]:
        raise SystemExit(filename + ': Provisioning profile does not match the explicit IOS_BUNDLE_ID target.')
    if p.get('ProvisionedDevices') is not None or p.get('ProvisionsAllDevices') or e.get('get-task-allow'):
        raise SystemExit(filename + ': Use an App Store Connect distribution profile, not development/ad hoc/enterprise.')
    if p['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise SystemExit(filename + ': Provisioning profile has expired.')
    certs = {hashlib.sha1(cert).hexdigest().upper() for cert in p.get('DeveloperCertificates', [])}
    matching = valid & certs
    if not matching:
        raise SystemExit(filename + ': No valid certificate/private-key identity matches the provisioning profile.')
    import uuid
    uuid.UUID(p['UUID'])
    return p['UUID'], matching

profile_uuid, app_identities = validate_profile('profile.plist', bundle)
widget_uuid, widget_identities = validate_profile('widget-profile.plist', bundle + '.widgets')
matching = sorted(app_identities & widget_identities)
if not matching:
    raise SystemExit('App and widget profiles must share an installed distribution identity.')
(root / 'profile-uuid').write_text(profile_uuid)
(root / 'widget-profile-uuid').write_text(widget_uuid)
(root / 'identity').write_text(matching[0])
options = {
    'method': 'app-store-connect',
    'destination': 'export',
    'teamID': team,
    'signingStyle': 'manual',
    'signingCertificate': matching[0],
    'provisioningProfiles': {bundle: profile_uuid, bundle + '.widgets': widget_uuid},
    'manageAppVersionAndBuildNumber': False,
}
(root / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
# The CI build only modifies its disposable checkout; local device signing is unchanged.
plist_path = Path('Pacer/Info.plist')
info = plistlib.loads(plist_path.read_bytes())
number = os.environ['GITHUB_RUN_NUMBER']
attempt = os.environ['GITHUB_RUN_ATTEMPT']
if not number.isdecimal() or not attempt.isdecimal():
    raise SystemExit('Invalid GitHub build-number inputs.')
info['CFBundleVersion'] = number + '.' + attempt
# Dedicated issue-only PAT is injected into the private signed build, never source.
info['AppChangeGitHubToken'] = os.environ['APP_CHANGE_GH_TOKEN']
plist_path.write_bytes(plistlib.dumps(info))
widget_path = Path('PacerWidgets/Info.plist')
widget_info = plistlib.loads(widget_path.read_bytes())
widget_info['CFBundleVersion'] = info['CFBundleVersion']
widget_info['CFBundleShortVersionString'] = info['CFBundleShortVersionString']
widget_path.write_bytes(plistlib.dumps(widget_info))
PY

profile_uuid="$(cat "$signing_dir/profile-uuid")"
widget_uuid="$(cat "$signing_dir/widget-profile-uuid")"
identity="$(cat "$signing_dir/identity")"
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profile_dir"
installed_profile="$profile_dir/$profile_uuid.mobileprovision"
cp "$signing_dir/app.mobileprovision" "$installed_profile"
installed_widget_profile="$profile_dir/$widget_uuid.mobileprovision"
cp "$signing_dir/widget.mobileprovision" "$installed_widget_profile"

xcodebuild -project Pacer.xcodeproj -scheme Pacer -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$signing_dir/Pacer.xcarchive" \
    DEVELOPMENT_TEAM="$IOS_TEAM_ID" PACER_APP_BUNDLE_ID="$IOS_BUNDLE_ID" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" \
    PACER_APP_PROFILE_UUID="$profile_uuid" PACER_WIDGET_PROFILE_UUID="$widget_uuid" \
    CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER.$GITHUB_RUN_ATTEMPT" archive
# Reject an archive with mismatched identities/versions before exporting/uploading.
python3 - <<'PYARCHIVE'
import os, plistlib, subprocess
from pathlib import Path
archive = Path(os.environ['PACER_SIGNING_DIR']) / 'Pacer.xcarchive/Products/Applications'
apps = list(archive.glob('*.app'))
if len(apps) != 1:
    raise SystemExit('Expected exactly one archived app.')
app = apps[0]
widget = app / 'PlugIns/PacerWidgets.appex'
expected_build = os.environ['GITHUB_RUN_NUMBER'] + '.' + os.environ['GITHUB_RUN_ATTEMPT']
app_info = plistlib.loads((app / 'Info.plist').read_bytes())
for product, bundle in [(app, os.environ['IOS_BUNDLE_ID']),
                        (widget, os.environ['IOS_BUNDLE_ID'] + '.widgets')]:
    info = plistlib.loads((product / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != bundle or info.get('CFBundleVersion') != expected_build:
        raise SystemExit('Archived bundle identifier or build number mismatch: ' + product.name)
    if info.get('CFBundleShortVersionString') != app_info['CFBundleShortVersionString']:
        raise SystemExit('App and widget marketing versions differ.')
    subprocess.run(['codesign', '--verify', '--strict', str(product)], check=True)
print('Verified app and embedded widget identities, versions, and signatures.')
PYARCHIVE

xcodebuild -exportArchive -archivePath "$signing_dir/Pacer.xcarchive" \
    -exportPath "$signing_dir/export" -exportOptionsPlist "$signing_dir/ExportOptions.plist"

export API_PRIVATE_KEYS_DIR="$signing_dir/private_keys"
python3 scripts/upload-testflight.py "$signing_dir/export"
{
    echo '### TestFlight upload accepted'
    echo "Build: $GITHUB_RUN_NUMBER.$GITHUB_RUN_ATTEMPT"
    echo 'Apple still needs to process the build. Check the TestFlight tab for processing, compliance, and tester availability.'
} >> "$GITHUB_STEP_SUMMARY"
