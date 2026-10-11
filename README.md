# Speed Up or Slow Down

A tiny native iPhone app for outdoor jogging. Set a target pace (minutes/km or minutes/mile),
start a run, and hear playful praise or progressively stronger pace corrections.
Running needs no account, server, API key, or external sensor. Optional change requests connect directly to GitHub.

## Use the app

Install the private TestFlight build, allow Location access **While Using the App**
with **Precise Location** enabled, set your target pace, and tap **Start run** outdoors.
Keep the phone with you and allow at least 10 seconds of usable GPS readings.

Adjust the target during a jog with the slider or **Faster / Slower** buttons.
Each press changes the target by 15 seconds per selected unit. Changes apply to
incoming GPS readings without resetting the run. **Stop run** ends tracking;
starting again resets the totals.

Open the gear button for **Settings**:

- **Colorful appearance:** optionally adds teal, orange, and purple accents and
  softly tinted cards to the run screen. Off by default; text stays in the
  system's adaptive colors for light and dark appearances.
- **Kilometres / Miles:** changes pace and distance displays while preserving
  the physical target and run totals. The target range is 4:00–12:00/km,
  approximately 6:26–19:19/mile.
- **Spoken coaching:** enables or silences audio cues.
- **Haptic coaching:** optional vibration cues, off by default, independent of
  speech. While the app is active, success feedback means on target, warning
  feedback means speed up, and error feedback means slow down. Gentle and strong
  corrections share the same pattern. iOS and device settings control delivery;
  haptics are not guaranteed in the background or with the screen locked.
- **Voice:** selects an installed English iOS voice; **Preview voice** auditions
  it. Voices come from the phone, not from bundled recordings. If a saved voice
  becomes unavailable, coaching falls back to the default US English voice.
- **Change app:** submits a suggestion directly from the app.

Appearance, units, spoken and haptic coaching preferences, and voice selection are remembered between launches.
The app requests music ducking while it speaks and releases the audio session
after each cue. Its icon and installed name are **Speed Up or Slow Down**.

## Build locally

1. On a Mac with Xcode, open `Pacer.xcodeproj` and select the **Pacer** scheme.
   The project and internal Swift package retain their original names.
2. Choose an iOS 17+ simulator to try the UI, or connect an iPhone and select
   your development team under **Signing & Capabilities**. A free Personal Team
   supports local device testing, subject to Apple's provisioning limits.
3. Build and run. A simulator cannot validate real jogging pace or background audio.

CI uses **Xcode 26.2**. Signed TestFlight distribution uses the paid team and
bundle identifier configured in CI, overriding local development signing.
Local and unsigned builds have change submission disabled unless the dedicated
issue-only credential is configured; jogging and voice previews work without it.
See [TESTFLIGHT.md](TESTFLIGHT.md) for manual distribution and
[TESTFLIGHT-CI.md](TESTFLIGHT-CI.md) for automatic uploads.

## How it measures pace

Core Location supplies GPS speed and accuracy estimates from the iPhone's
built-in positioning hardware. The app averages speed over a rolling 15-second
window, then converts it to minutes/km or minutes/mile. It rejects old fixes, poor accuracy,
negative speed, and speeds above 8 m/s. It waits for 10 seconds of samples before
coaching and never speaks more often than once every 30 seconds. Below 0.5 m/s it shows no
numeric pace and can prompt you to speed up.

### Coaching personality and timing

The app has 100 short phrases: 40 affirmations and 15 each for gentle/strong
speed-up and slow-down cues. Each category is shuffled, with no repeats until
its list is exhausted and no immediate repeat across shuffle cycles.

| Difference from target | Coaching | Minimum time since last cue |
| --- | --- | --- |
| Within ±20 sec/km (about ±32 sec/mile) | Playful encouragement | 120 seconds |
| More than 20, up to 60 sec/km off (about 32–97 sec/mile) | Gentle directional nudge | 60 seconds |
| More than 60 sec/km off (about 97 sec/mile) | Clearer directional correction | 30 seconds |

These are delays between eligible cues, not fixed alarms: GPS still needs to be
usable and either spoken coaching available with speech idle or haptic coaching
enabled while the app is active. Both outputs share the same cooldown. The first cue can play after the
10-second GPS settling window. Worsening pace shortens the next wait to 30 seconds;
getting back on target slows the chatter down again. Unit changes preserve the
same physical bands. Disabling both coaching outputs does not consume the cue cooldown.

Examples: “Your feet have formed a successful committee,” “Add a sprinkle of
hustle,” and “We ordered a jog, not a rocket launch.”

Distance is an **estimate** from integrating accepted speed readings. Gaps longer
than eight seconds are excluded, so distance can undercount during outages.
No route is recorded. Run state exists only in memory; there is no saved history,
pause button, Apple Watch support, or HealthKit integration.

Speech uses an audio session that requests music ducking and interruption of
other spoken audio, then releases the session after each cue. Background location
and audio modes are declared to support a run with the screen locked.

## What won't work or isn't guaranteed

- **Treadmills / indoor jogging:** GPS does not measure belt speed or running in
  place. Step-based indoor pace would need Core Motion plus stride calibration;
  it is not implemented.
- **Instant pace changes:** smoothing deliberately delays feedback by roughly
  10–15 seconds. This is for steady jogging, not sprint intervals.
- **Reliable GPS everywhere:** tunnels, tall buildings, tree cover, reduced
  location accuracy, or disabled Location Services can prevent coaching. A stale
  signal shows no pace; there are no estimated nudges during outages.
- **Tracking after termination:** force-quitting, system termination, or rebooting
  ends this in-memory run. It does not automatically resume. Continuous background
  location is requested while a user-started run is active; iOS controls delivery.
- **Audio in every situation:** calls, Siri, audio route changes, muted media
  volume, and other apps can interrupt or suppress speech. Mixing/ducking and
  locked-screen playback need testing with your actual headphones and music app.
  The app cannot control another app's volume or guarantee it resumes.
- **Perfect distance or race-grade accuracy:** GPS noise and filtered gaps affect
  pace and distance. Continuous GPS also uses battery. This is not a safety or
  medical device.
- **Building iOS on this Linux cloud machine:** Apple's SDKs, simulator, signing,
  and device deployment require macOS/Xcode. Linux can test the pure Swift pace
  engine, but cannot validate the SwiftUI, Core Location, or audio integration.

## Suggest a change

Open **Settings → Change app**, describe the desired behavior, optionally add your
name, and tap **Send request**. No tester account or GitHub login is required.
The app creates a **public GitHub issue**, saves drafts after failed submissions,
and shows a receipt link when delivery is confirmed. Retry handling checks recent
requests before reposting. Leave credentials and private details out of requests.

The improvement loop is:

1. A tester submits a request from the app.
2. A maintainer applies **`ready-for-agent`** to approve agent work. Maintainer
   replies on an approved open issue restart the agent with the full discussion,
   including answers to clarification questions. Agent comments do not restart it,
   and an existing agent PR prevents duplicate proposals.
3. Codex evaluates the request and implements an accepted change on a branch,
   or asks for clarification or explains why it cannot proceed.
4. A separate job checks the proposal and runs Swift tests and unsigned iOS builds.
5. The workflow opens a PR for owner review. It never merges automatically.
6. Merging an app change into `main` starts private TestFlight delivery.

The agent initially works only on existing app Swift files, core code, tests, and
README. Signing, dependencies, privacy declarations, project files, and automation
remain outside its permitted edit scope. See [APP-CHANGE-AGENT.md](APP-CHANGE-AGENT.md)
for credentials, limits, and recovery.

Anonymous submission uses a **dedicated repository-scoped PAT with Issues
read/write only**, injected into the signed app by CI. It can be extracted from
the app; this is an explicitly accepted tradeoff for the small friends/TestFlight
group. The public source contains no token. Neither the OpenAI API key nor the
code-writing agent token is shipped in the app.

## Automatic private delivery

GitHub Actions validates **main pushes, PR updates, and manual runs**. Branch
pushes do not duplicate PR checks. The release job signs, exports, and uploads
only when needed:

- App code, assets, project settings, or package inputs change on `main`.
- Documentation, test-only, and automation changes skip TestFlight uploads.
- Superseded CI runs are cancelled; stale main commits and already-uploaded
  commits are skipped before archiving.
- Manual runs validate only by default. Select **Force a TestFlight upload after
  validation** to upload a replacement build or pick up rotated credentials.

Uploads are serialized and receive unique build numbers. Apple must process each
upload before it is available. An internal group with automatic distribution and
TestFlight's **Automatic Updates** setting completes delivery to testers. The
pipeline does not publish an App Store release. TestFlight builds expire after
90 days.

The agent and feedback smoke-test workflows never sign or export apps.
See [TESTFLIGHT-CI.md](TESTFLIGHT-CI.md) for setup and the complete trigger policy.

## Development checks

The same `Sources/PacerCore/PaceEngine.swift` is compiled into the iOS app and
the standalone Swift package. With Swift 5.9 or later:

```sh
swift test
```

Without a local Swift installation, use the official Swift Docker image:

```sh
docker run --rm -v "$PWD:/app" -w /app swift:6.0.3 swift test --jobs 2
```

On a Mac, also compile the actual app without device signing:

```sh
xcodebuild -project Pacer.xcodeproj -scheme Pacer -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

The shared app scheme has no XCTest target: use **`swift test`** for core tests,
not an empty `xcodebuild test` run. GitHub Actions runs core tests and the iOS
simulator build on macOS once these files are pushed. A simulator build cannot
prove real GPS accuracy or background audio behavior.

CI also runs the Python pipeline checks:

```sh
python3 -m unittest discover -s scripts/tests -v
```

The **iOS build and pace tests** workflow uses GitHub's `macos-15` hosted runner
with Xcode 26.2 for Swift tests, simulator builds, and unsigned device Release
builds. Unsigned validation needs no Apple signing credentials. The separate
release job uses the private `testflight` environment after validation passes.
GitHub Actions and OpenAI API usage are subject to the owner's billing limits.

Before relying on coaching, verify on a real iPhone: changing the target during a
run, switching units without changing the target speed or resetting distance,
location denial and Precise
Location off, settling outdoors, both cue directions, the cooldown, loss and
recovery of GPS, music/headphone ducking, several minutes with the screen locked,
stopping (no subsequent cues/location indicator), and force-quit behavior.

No location data leaves the app. There is no analytics, backend, or microphone access. Running needs no credentials; optional change requests use the issue-only credential injected into TestFlight builds.
