# Issue-to-PR app changes

Workflow: **Propose app change with Codex**. A repository maintainer applies `ready-for-agent` to an open issue (or manually runs the workflow with that issue number). The agent evaluates the request, implements an accepted change, and returns a structured decision. A separate trusted gate restricts which files can change. Swift tests and unsigned simulator/device builds must pass before a separate job publishes a PR. Declined requests and clarification questions become issue comments.

## Credentials

Create two **repository Actions secrets**, not TestFlight environment secrets:

- `OPENAI_API_KEY`: OpenAI API key with Responses API access and a project spending limit/alerts. API use is billed separately from ChatGPT.
- `CODEX_GH_TOKEN`: fine-grained GitHub token restricted to `batemapf/pacer`, with Contents, Issues, and Pull requests read/write. The token owner's repository account must have write access. No Administration, Secrets, Workflows, or Apple signing permissions are needed for the runtime token. Its branch pushes and PRs trigger the normal CI checks, unlike the default Actions token.

The OpenAI key is given only to the official pinned Codex action, which provides protected API access. The GitHub publishing token is given only to a separate job after the agent exits and checks pass. Neither job uses the `testflight` environment. No automatic merging or release occurs. After you review and merge a PR, the existing main pipeline uploads to TestFlight.

The CLI is pinned to 0.162.1 and runs with the workspace permission profile and sudo removed. It can work offline with local files; changes requiring external dependency downloads are outside this initial scope. A 10-minute agent timeout and 20-minute job timeout bound execution time; set spending controls on the OpenAI project as well.

## Initial scope

Only existing `Pacer/ContentView.swift`, `Pacer/RunTracker.swift`, `Pacer/PacerApp.swift`, `Sources/PacerCore/*.swift`, `Tests/PacerCoreTests/*.swift`, and `README.md` may change. Changes to app identity, privacy permissions, dependencies, signing, project files, workflows, scripts, or policy need owner implementation. The independent gate rejects symlinks, new files, more than 10 changed files, or a patch over 200 KB. Read `.github/codex/change-policy.md` for the agent's product rules.

## Usage and recovery

1. Create an issue describing the desired behavior and an example of success. Avoid credentials or private user data: this repository is public.
2. A maintainer applies `ready-for-agent`. Public users applying no label cannot trigger the agent.
3. Inspect the workflow run, then the issue comment and proposed PR. The owner decides whether to merge.
4. If a run fails before creating a PR, fix the cause and manually rerun the workflow with the issue number. An existing PR for `codex/issue-N` prevents another agent proposal for that issue. For further work after a PR exists, use a new issue.

Concurrency prevents simultaneous jobs for the same issue. GitHub may replace older pending jobs for that issue; the latest request remains queued. This is a one-pass prototype: no automatic repair loop, automatic merge, yet. A request that needs clarification can be edited and manually resubmitted.

## Native anonymous requests

**Settings → Change app** sends a JSON POST directly to GitHub's issues API, without tester authentication. An optional name is unverified; GitHub attributes the issue to the token owner. Issues are public because this repository is public. The app includes its version/build but sends no location, pace data, or device identifier. A random request ID helps recover receipts after uncertain delivery; recent labeled issues are checked before retrying.

Create a **separate fine-grained PAT** restricted to `batemapf/pacer` with **Issues read/write only** and store it as `APP_CHANGE_GH_TOKEN` in repository Actions secrets or the `testflight` environment secrets. Do not reuse `CODEX_GH_TOKEN`, which can write app code. Choose an expiration and rotate this credential with a new TestFlight build before it expires.

The release script injects the PAT into the disposable build's Info.plist. It is never committed or printed. It **can be extracted from the distributed app**, so this shared credential is appropriate only for the owner's explicitly accepted friends/TestFlight use. The checked-in plist contains an empty value; unsigned/local builds disable submission unless locally configured. No API key or code-writing token is shipped. The upload job fails clearly if the issue-only secret is missing.

Native requests get only `app-change`, never `ready-for-agent`: a maintainer approves agent execution to protect the API budget. After that, the existing issue-to-PR workflow handles the request. No backend, Cloudflare account, or user login is needed.
