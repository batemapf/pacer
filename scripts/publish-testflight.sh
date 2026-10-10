#!/usr/bin/env bash
# Runs only on an ephemeral GitHub macOS runner. Never enable shell tracing.
set -euo pipefail
umask 077

for name in IOS_TEAM_ID IOS_BUNDLE_ID ASC_API_KEY_ID ASC_API_ISSUER_ID \
    IOS_DISTRIBUTION_P12_BASE64 IOS_DISTRIBUTION_P12_PASSWORD \
    IOS_APP_STORE_PROFILE_BASE64 ASC_API_KEY_P8_BASE64; do
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
cleanup() {
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    if [[ -n "$installed_profile" ]]; then rm -f "$installed_profile"; fi
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
security find-identity -v -p codesigning "$keychain" > "$signing_dir/identities.txt"

python3 - <<'PY'
import datetime, hashlib, os, plistlib, re
from pathlib import Path
root = Path(os.environ['PACER_SIGNING_DIR'])
p = plistlib.loads((root / 'profile.plist').read_bytes())
e = p.get('Entitlements', {})
team = os.environ['IOS_TEAM_ID']
bundle = os.environ['IOS_BUNDLE_ID']
if team not in p.get('TeamIdentifier', []) or e.get('com.apple.developer.team-identifier') != team:
    raise SystemExit('Provisioning profile does not match IOS_TEAM_ID.')
prefixes = p.get('ApplicationIdentifierPrefix', [])
if e.get('application-identifier') not in [prefix + '.' + bundle for prefix in prefixes]:
    raise SystemExit('Provisioning profile does not match the explicit IOS_BUNDLE_ID.')
if p.get('ProvisionedDevices') is not None or p.get('ProvisionsAllDevices') or e.get('get-task-allow'):
    raise SystemExit('Use an App Store Connect distribution profile, not a development/ad hoc/enterprise profile.')
if p['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit('Provisioning profile has expired.')
identities = (root / 'identities.txt').read_text()
valid = set(re.findall(r'\b[0-9A-F]{40}\b', identities))
certs = {hashlib.sha1(cert).hexdigest().upper() for cert in p.get('DeveloperCertificates', [])}
matching = sorted(valid & certs)
if not matching:
    raise SystemExit('No valid certificate/private-key identity matches the provisioning profile.')
profile_uuid = p['UUID']
import uuid
uuid.UUID(profile_uuid)
(root / 'profile-uuid').write_text(profile_uuid)
(root / 'identity').write_text(matching[0])
options = {
    'method': 'app-store-connect',
    'destination': 'export',
    'teamID': team,
    'signingStyle': 'manual',
    'signingCertificate': matching[0],
    'provisioningProfiles': {bundle: profile_uuid},
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
plist_path.write_bytes(plistlib.dumps(info))
PY

profile_uuid="$(cat "$signing_dir/profile-uuid")"
identity="$(cat "$signing_dir/identity")"
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profile_dir"
installed_profile="$profile_dir/$profile_uuid.mobileprovision"
cp "$signing_dir/app.mobileprovision" "$installed_profile"

xcodebuild -project Pacer.xcodeproj -scheme Pacer -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$signing_dir/Pacer.xcarchive" \
    DEVELOPMENT_TEAM="$IOS_TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_ID" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" \
    PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" archive
xcodebuild -exportArchive -archivePath "$signing_dir/Pacer.xcarchive" \
    -exportPath "$signing_dir/export" -exportOptionsPlist "$signing_dir/ExportOptions.plist"

export API_PRIVATE_KEYS_DIR="$signing_dir/private_keys"
xcrun altool --upload-app --type ios --file "$signing_dir/export/Pacer.ipa" \
    --apiKey "$ASC_API_KEY_ID" --apiIssuer "$ASC_API_ISSUER_ID"
{
    echo '### TestFlight upload accepted'
    echo "Build: $GITHUB_RUN_NUMBER.$GITHUB_RUN_ATTEMPT"
    echo 'Apple still needs to process the build. Check the TestFlight tab for processing, compliance, and tester availability.'
} >> "$GITHUB_STEP_SUMMARY"
