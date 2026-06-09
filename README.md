# Spatial Audio Router

Menu bar app for keeping native macOS apps as their own renderers while rerouting selected app audio through a local Apple spatialized monitor path.

This does **not** toggle Apple Spatial Audio inside Spotify. There is no public API that lets a helper process force Apple Spatial Audio onto another signed Chromium/CoreAudio app. The workable approach here is:

1. Find CoreAudio process objects for visible apps.
2. Create a macOS Core Audio Process Tap for those objects.
3. Mute selected apps while tapped, so they do not double-play.
4. Render the tapped stereo stream to the current system output with Apple's `AUSpatialMixer`.
5. Optionally feed CoreMotion headphone yaw/pitch/roll into the spatial mixer head-pose parameters.

## Requirements

- macOS 14.2 or newer for Core Audio Process Taps.
- Xcode command line tools.
- At least one native macOS app running with CoreAudio-visible audio.
- System Audio Recording permission when macOS prompts for it.

## Build

```sh
make app
```

## Run

Launch the menu bar app:

```sh
make run
```

Click the waveform icon in the macOS menu bar, then use the native switches in the popover to spatialize any listed app. The helper recreates one shared process tap for all selected apps.

`make run-head` launches the same menu bar app with headphone head tracking enabled by default. Head tracking uses CoreMotion from the app bundle and may trigger macOS motion permission. It only becomes active on output routes and headphones that expose headphone motion data.

```sh
make run-head
```

For diagnostics without starting the tap, list CoreAudio-visible apps:

```sh
make list
```

For the old terminal Spotify-only diagnostic path:

```sh
make run-spotify
make run-spotify-head
```

The terminal Spotify diagnostic runs fixed spatial audio even when invoked with `run-spotify-head`; CoreMotion headphone tracking is only started by the LaunchServices menu bar app (`make run-head`) so macOS can apply the bundled Motion permission description.

## Chromium / CEF Experiment

The repo also includes a research path for forcing Spotify's bundled Chromium audio output toward Apple's AVFoundation playback backend:

```sh
make inspect-cef
make run-cef-avf
make run-cef-avf-logged
make sample-audio-stack
make native-probe
make run-native-probe
make run-probe-copy
make run-probe-unit
make run-probe-object
make inspect-probe-log
```

`make inspect-cef` reproduces the local Spotify/CEF inspection. `make run-cef-avf` quits Spotify and relaunches it with Chromium's `MacAVFoundationPlayback` feature enabled. `make run-cef-avf-logged` launches the Spotify executable directly and writes Chromium audio logs under `logs/` so we can search for `AVFoundationOutputStream` or `AUHALStream`. `make sample-audio-stack` samples the active Spotify process and searches for native audio-renderer thread names. `make run-native-probe` tries a DYLD interpose probe for native CoreAudio calls against the official app. `make run-probe-copy` copies Spotify into `build/`, ad-hoc re-signs that copy for instrumentation, and runs the same probe without modifying `/Applications/Spotify.app`. After launching, play a track and check the AirPods menu in Control Center.

For the copied probe app, click Play in the instrumented Spotify window rather than using AppleScript. Then run `make inspect-probe-log`. The copied app uses `com.spotify.client.probe` by default so it does not collide with the official app's runtime state; it may need separate login/cache initialization.

`run-probe-copy` defaults to `PROBE_MODE=load`, which only verifies that the probe can be injected without destabilizing Spotify. Narrower interpose modes are available as Make targets:

```sh
make run-probe-unit
make run-probe-object
```

`make run-probe-component` and `make run-probe-audio` are disabled by default. The component interpose proved Spotify creates Apple's default output AudioUnit (`auou` / `def ` / `appl`), but it recurses inside `AudioComponentInstanceNew` and can close Spotify when playback starts. Continue with `make run-probe-unit` or `make run-probe-object`.

See [docs/cef-chromium-spatial-research.md](docs/cef-chromium-spatial-research.md) for the evidence and decision tree.

`make run` opens the generated `build/SpotifyNativeSpatial.app` bundle as a menu bar app and kills any previous helper instance first so duplicate menu bar icons do not accumulate.

## Current State

This is a prototype. The process-tap and muted reroute path is the important part. The monitor renderer now uses Apple's AudioToolbox spatial mixer with stereo ambience-bed rendering, output-type selection for headphones / built-in speakers / external speakers, personalized HRTF auto mode, and optional CoreMotion headphone tracking.

The fixed spatial path is tuned as a clean music profile: it uses Apple's `UseOutputType` spatialization, keeps stereo input as an ambience bed, disables the mixer's default reverb wetness, locks playback rate at 1.0, and applies a short startup fade plus transparent peak soft-limiting after the mixer. Normal-level samples are not changed by the post stage.

The AirPods Spatial Audio setting may still not present the original app itself as supported content because that app remains a separate CoreAudio client and the helper outputs processed PCM. The working path is the helper-rendered spatial monitor feed.

CoreAudio exposes process-level audio, not browser tab identity. For browsers, the menu can spatialize Chrome/Brave/etc. process audio; it cannot reliably promise one arbitrary tab unless the browser maps that tab to a distinct CoreAudio process that can be identified.
