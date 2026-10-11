# Pacer

A tiny native iPhone app for outdoor jogging. Set a target pace (minutes/km or minutes/mile),
start a run, and hear playful praise or progressively stronger pace corrections.
No account, server, API key, or external sensor.

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

An app icon is included and selected for both Debug and Release builds. Distribution
provisioning still requires your Apple developer team; this is a development
prototype, not an App Store release.

## How it measures pace

Core Location supplies GPS speed and accuracy estimates from the iPhone's
built-in positioning hardware. Pacer averages speed over a rolling 15-second
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
usable, coaching enabled, and speech idle. The first cue can play after the
10-second GPS settling window. Worsening pace shortens the next wait to 30 seconds;
getting back on target slows the chatter down again. Unit changes preserve the
same physical bands. Muting coaching does not consume the cue cooldown.

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
  Pacer cannot control another app's volume or guarantee it resumes.
- **Perfect distance or race-grade accuracy:** GPS noise and filtered gaps affect
  pace and distance. Continuous GPS also uses battery. This is not a safety or
  medical device.
- **Building iOS on this Linux cloud machine:** Apple's SDKs, simulator, signing,
  and device deployment require macOS/Xcode. Linux can test the pure Swift pace
  engine, but cannot validate the SwiftUI, Core Location, or audio integration.

## Suggest a change

Open **Settings → Change app**, describe the desired behavior, optionally add your name, and tap **Send request**. No tester account or GitHub login is required. The app creates a public GitHub issue and shows a receipt link; drafts survive failed submissions. Leave credentials and private details out of requests.

A maintainer applies `ready-for-agent` to approve agent work. Codex proposes a PR, independent checks must pass, and owner review is required before merging. See [APP-CHANGE-AGENT.md](APP-CHANGE-AGENT.md) for setup and scope.
