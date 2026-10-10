# Pacer

A tiny native iPhone app for outdoor jogging. Set a target pace (minutes/km or minutes/mile),
start a run, and hear “Speed up” or “Slow down” when your measured pace is more
than 20 seconds/km off target. No account, server, API key, or external sensor.

## Run on an iPhone

1. On a Mac with Xcode 16 or later, open `Pacer.xcodeproj`.
2. Select the **Pacer** scheme and your iPhone (iOS 17 or later).
3. In Signing & Capabilities, select your Apple development team. Change the
   bundle identifier if needed for your team. A free Personal Team can be used
   for local testing, subject to Apple's provisioning limits.
4. Build and run. Allow Location access **While Using the App**, with **Precise
   Location** on. Start the run while the app is in the foreground.
5. Go outside, keep the phone with you, and allow at least 10 seconds of usable
   GPS readings. Use the Spoken coaching toggle to silence cues. Stop the run
   when finished; starting again resets the totals. Adjust the target during a run
   with the slider or **Faster / Slower** buttons (15 seconds per selected unit).
   Changes apply to the next usable GPS reading without restarting the run; the
   30-second coaching cooldown still applies.

Use the **Kilometres / Miles** toggle to change both pace and distance displays,
including during a run. Switching units preserves the physical target pace and
all run totals. Your unit preference is remembered. The target range covers the
same speeds: 4:00–12:00/km, approximately 6:26–19:19/mile.

An app icon and distribution provisioning are not included; this is a development
prototype, not an App Store release.

## How it measures pace

Core Location supplies GPS speed and accuracy estimates from the iPhone's
built-in positioning hardware. Pacer averages speed over a rolling 15-second
window, then converts it to minutes/km or minutes/mile. It rejects old fixes, poor accuracy,
negative speed, and speeds above 8 m/s. It waits for 10 seconds of samples before
coaching and limits cues to once every 30 seconds. Below 0.5 m/s it shows no
numeric pace and can prompt you to speed up.

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
  Pacer cannot control another app's volume or guarantee it resumes.
- **Perfect distance or race-grade accuracy:** GPS noise and filtered gaps affect
  pace and distance. Continuous GPS also uses battery. This is not a safety or
  medical device.
- **Building iOS on this Linux cloud machine:** Apple's SDKs, simulator, signing,
  and device deployment require macOS/Xcode. Linux can test the pure Swift pace
  engine, but cannot validate the SwiftUI, Core Location, or audio integration.

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

The **iOS build and pace tests** workflow also supports **Run workflow** in the
repository's Actions tab. It uses GitHub's standard `macos-15` hosted runner,
read-only repository permissions, and a 15-minute timeout. No Apple signing
secrets or paid Apple developer account are needed for this simulator build.
GitHub Actions must be enabled for the repository and allow `actions/checkout`.
Private repositories use the account's included Actions allowance or paid usage;
check Actions billing and budgets if GitHub refuses to start a job.

Before relying on coaching, verify on a real iPhone: changing the target during a
run, switching units without changing the target speed or resetting distance,
location denial and Precise
Location off, settling outdoors, both cue directions, the cooldown, loss and
recovery of GPS, music/headphone ducking, several minutes with the screen locked,
stopping (no subsequent cues/location indicator), and force-quit behavior.

No location data leaves the app. There is no analytics, backend, microphone access,
or credential requirement.
