# Set up automatic private TestFlight uploads

Repository: https://github.com/batemapf/pacer

The workflow is implemented in `.github/workflows/check.yml`. On a push to `main`, it runs the tests, simulator build, and unsigned device Release build. If those pass, the repository variable `TESTFLIGHT_ENABLED` is exactly `true`, and the push changes app code, assets, project settings, or release tooling, it signs an archive and uploads it to App Store Connect. Documentation, test-only, and agent-automation changes still run validation but skip TestFlight. The change check compares the complete push range, including merges and deletions. Manual workflow runs explicitly request an upload regardless of changed files. It can also be run manually using **Actions → iOS build and pace tests → Run workflow** on `main`.

**Current status:** uploads are disabled by default. The GitHub integration cannot create environments, variables, or secrets (HTTP 403). The following configuration must be created by a repository admin. There are no Apple signing secrets stored by this setup.

## 1. Confirm the Apple app identity

The Apple Developer account owner has an **individual paid membership**. App Store Connect Admin access alone does not provide signing access through your own Xcode account. The owner must prepare the signing assets under his membership.

In App Store Connect, open **Speed Up or Slow Down → App Information** and record the exact Bundle ID. In the Apple Developer account, record the paid **Team ID**. Do not use the free Personal Team from the local Xcode project. CI overrides that local team without changing the checked-in project.

The source project is still called Pacer and the UI still says Pacer. This pipeline does not rename the app.

## 2. Create the GitHub configuration placeholders

If using Codex on the owner's computer, authenticate GitHub CLI as a repository admin and run **`python3 scripts/configure-testflight.py`** from the checkout. It creates the non-secret placeholders below, keeps existing values, and restricts a newly created environment to `main`. It never creates fake signing secrets. If the CLI is using an integration token with insufficient permissions, use the GitHub settings UI instead.

Open **repository Settings → Environments → New environment**. Name it exactly **`testflight`**. Restrict deployment branches to `main`. Do not add required reviewers if uploads should run unattended on every commit.

Create these **environment variables** under `testflight`:

| Name | Initial placeholder | Replace with |
| --- | --- | --- |
| `IOS_TEAM_ID` | `SET_ME` | Paid Apple Team ID, 10 characters |
| `IOS_BUNDLE_ID` | `SET_ME` | Exact explicit Bundle ID of the existing app record |
| `ASC_API_KEY_ID` | `SET_ME` | App Store Connect team API key ID |
| `ASC_API_ISSUER_ID` | `SET_ME` | Team API issuer UUID |

Under **Settings → Secrets and variables → Actions → Variables**, create the **repository variable** `TESTFLIGHT_ENABLED` with value **`false`**. This switch must be a repository variable: environment variables are not available when GitHub evaluates the job's condition.

Do not create fake credential values. GitHub cannot store empty secret placeholders. Create the four secret names below only when their real values are ready.

## 3. Export a distribution signing identity

On the account owner's Mac, use Xcode or **Apple Developer → Certificates, Identifiers & Profiles** to create an **Apple Distribution** certificate. Creating a certificate requires the matching private key on that Mac. Reuse a suitable existing certificate rather than revoking unrelated certificates.

In **Keychain Access → My Certificates**, select the distribution certificate and its private key, then export them together as a password-protected `.p12`. A `.cer` file without its private key is insufficient.

Encode it on macOS:

```sh
base64 -i /path/to/distribution.p12 | pbcopy
```

Immediately paste into the GitHub **`testflight` environment secret** `IOS_DISTRIBUTION_P12_BASE64`. Add the export password as `IOS_DISTRIBUTION_P12_PASSWORD`. Clear the clipboard afterward. Do not send either value to Codex chat, commit it, or paste it into an issue.

## 4. Create an App Store distribution profile

In the owner's **Certificates, Identifiers & Profiles → Profiles**, create an **App Store Connect distribution** profile. Select the exact explicit app ID and the distribution certificate exported above. Download the `.mobileprovision` file.

```sh
base64 -i /path/to/app.mobileprovision | pbcopy
```

Paste into the **`testflight` environment secret** `IOS_APP_STORE_PROFILE_BASE64`, then clear the clipboard. Do not use development, ad hoc, or enterprise profiles. The script checks team, bundle ID, expiry, and certificate matching before archiving.

## 5. Create a team App Store Connect API key

In **App Store Connect → Users and Access → Integrations → App Store Connect API**, request API access if required. Create a **team API key** with an appropriate role for build uploads, such as **App Manager**. This implementation expects a team key with an Issuer ID; do not substitute an individual API key.

Download the `.p8` private key. Apple normally permits the download only once; keep a secure backup. Record the Key ID and Issuer ID in the environment variables above.

```sh
base64 -i /path/to/AuthKey_KEYID.p8 | pbcopy
```

Paste into the **`testflight` environment secret** `ASC_API_KEY_P8_BASE64` and clear the clipboard.

The four secret names are:

```text
IOS_DISTRIBUTION_P12_BASE64
IOS_DISTRIBUTION_P12_PASSWORD
IOS_APP_STORE_PROFILE_BASE64
ASC_API_KEY_P8_BASE64
```

## 6. Enable and prove the first upload

Replace all `SET_ME` variables with the real non-secret identifiers. Confirm the four secrets are present. Set the **repository** variable `TESTFLIGHT_ENABLED` to **`true`**.

Run the workflow manually on `main`. Check that the tests and both unsigned builds pass, then that **Upload private TestFlight build** succeeds. The script installs signing assets in a temporary keychain, manually signs with the paid team, exports an IPA, uploads using `altool`, and removes its temporary credentials on exit. No signed app or signing assets are published as GitHub artifacts.

Build numbers are generated as **`GITHUB_RUN_NUMBER.GITHUB_RUN_ATTEMPT`**, replacing the literal `1` only inside the CI checkout. Each run/retry gets a distinct build number. If the app already has larger build numbers, adjust the numbering scheme before enabling CI. The app version remains `1.0`.

An accepted upload is not proof of TestFlight availability. Wait for Apple processing and resolve any compliance or processing issues in App Store Connect. For this app, answer encryption questions based on the actual build; the app does not implement custom encryption.

## 7. Make processed builds available privately

As an App Store Connect Admin, create an **internal tester group**, add yourself, and enable automatic distribution of new builds to that group if available. Internal testing does not require beta review. Do not enable public tester links or submit an App Store release.

External tester groups may require beta review and additional metadata. This workflow uploads builds; it does not submit an App Store version, bypass beta review, or manage tester invitations.

## 8. Maintenance and Codex computer-use handoff

- Renew expired certificates/profiles and update the corresponding secrets. Do not revoke unrelated signing assets.
- Each TestFlight build expires after 90 days. A new main commit or manual run uploads a replacement.
- Disable uploads at any time by setting `TESTFLIGHT_ENABLED=false`.
- Upload jobs are serialized. GitHub concurrency may replace older pending uploads with newer ones; every push runs validation, but not every queued commit is guaranteed a separate TestFlight upload.
- For a Codex computer-use session: the owner logs into Apple locally, authorizes the setup, then follows these steps. Never put passwords, `.p12`/`.p8` contents, base64 credentials, or private keys in chat, screenshots, git, or an issue. If secure secret entry cannot be performed without exposing values, stop at that step and let the owner enter them directly in GitHub settings.

Signed archives and real Apple uploads have not been tested yet because credentials are not configured. The first successful upload and processed TestFlight build are the acceptance checks for completing setup.
