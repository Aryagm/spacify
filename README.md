# Spacify

<p align="center"><img src="Resources/Banner.png" alt="Spacify: spatial audio for any Mac app"></p>

Spotify doesn't support Spatial Audio on the Mac. Neither does Chrome. Spacify fixes that.

Spacify is a menu bar app. Flip a switch and any app's audio plays through Apple's spatial audio engine, with AirPods head tracking. Apps that were never built for Spatial Audio sound like they were.

## Install

One command installs the latest release and launches it:

```sh
curl -fsSL https://raw.githubusercontent.com/Aryagm/spacify/main/install.sh | sh
```

Spacify is open source and not notarized. The script clears the Gatekeeper quarantine and signs the app locally. It's a dozen readable lines: [`install.sh`](install.sh). Prefer manual? Download the zip from [Releases](https://github.com/Aryagm/spacify/releases), drop the app in `/Applications`, and right-click it and choose Open the first time.

The binary is universal (Apple silicon + Intel). It needs **macOS 14.2 or newer**.

First run: click the earbuds icon in the menu bar. Toggle an app. Listen. macOS will ask for **System Audio Recording** permission. That permission is the process tap.

## What it does

Flip the switch next to an app. Spacify lifts its audio out of the normal playback path and re-renders it with `AUSpatialMixer`. That is the same spatializer behind Apple's own Spatial Audio.

- **Any audio app.** If CoreAudio can see it, Spacify can spatialize it. Streaming clients, browsers, games, video calls. Select several at once and they share one tap.
- **Native AirPods head tracking.** One switch anchors the sound stage in front of you. It uses the AirPods' own motion engine. It toggles live without stopping the music.
- **Tuned to your output.** Headphones get the binaural HRTF render, personalized where available. Speakers get Apple's speaker profiles.
- **Follows your devices.** Swap AirPods in or out and routing rebuilds itself on the new output. If a device changes its sample rate mid-route, the route rebuilds at the new rate instead of drifting off-pitch.
- **Remembers your setup.** Selections and preferences survive restarts. Routing resumes on its own.
- **No double audio.** Tapped apps are muted at the system level. You only hear the spatialized feed.

Spacify adds no DSP of its own. No EQ, no compression, no widening, no crossfeed. You hear Apple's render of the original stream and nothing else. A fixed music profile keeps the mixer clean: stereo stays an ambience bed, reverb is zeroed, playback rate is locked at 1.0. The one exception is a sub-second fade when a route starts or stops. That stops toggling from clicking. Steady-state audio is never touched.

## Why it exists

There is no public API to turn on Spatial Audio inside another app. macOS's built-in Spatialize Stereo only works for apps on supported playback paths. Spotify's Chromium audio stack never qualifies. Most non-Apple apps don't either.

Spacify takes the route that works. Tap the app's audio, mute the original, and render the stream through Apple's spatializer. Same engine. Same head tracking. One step downstream.

## Build from source

```sh
make app    # build the .app bundle
make run    # launch the menu bar app
```

You need macOS 14.2+ and the Xcode command line tools. `make run-head` launches with head tracking on, ignoring the saved preference. `make dist` produces the universal release zip.

Diagnostics:

```sh
make list               # print every CoreAudio-visible app and its processes
make run-spotify        # terminal-only Spotify render path
make run-spotify-head   # same, with head tracking
make test               # run the test suite
```

## How it works

```
 Selected apps                Spacify helper process                    Output device
┌──────────────┐   ┌─────────────────────────────────────────────┐   ┌──────────────┐
│ Spotify      │   │  Core Audio Process Tap                     │   │ AirPods /    │
│ Chrome       ├──▶│  (stereo mixdown, originals muted)          │   │ speakers     │
│ …            │   │                │                            │   │              │
└──────────────┘   │                ▼                            │   │              │
                   │  AUSpatialMixer (UseOutputType, HRTF,       ├──▶│              │
                   │  optional AirPods head tracking)            │   │              │
                   │                │                            │   │              │
                   │                ▼                            │   │              │
                   │  Layout bridge (zero-copy / vDSP)           │   │              │
                   └─────────────────────────────────────────────┘   └──────────────┘
```

1. **Discovery.** `AudioProcessResolver` lists CoreAudio process objects and maps them to their `.app` bundles. Multi-process apps group into one menu entry. A Chromium browser's many helpers show as one row.
2. **Capture.** Selected apps share one process tap (`CATapDescription(stereoMixdownOfProcesses:)`). The tap mutes the originals while it runs.
3. **Routing.** A private aggregate device wraps the default output and the tap. The output device is the clock. The tap is drift-compensated to that clock, so apps producing at a different sample rate stay pitch-correct. An IO proc on a `userInteractive` queue drives the render at the aggregate's rate.
4. **Spatialization.** `AUSpatialMixer` is configured at route start: `UseOutputType` spatialization, ambience-bed source mode, output type inferred from the device, personalized HRTF in auto mode (macOS 13+). Head tracking toggles on the live mixer. No rebuild. No interruption.
5. **Delivery.** The mixer's planar float output is bridged to the device's buffer layout and written straight into the IO proc's buffers.

Selection changes and device switches rebuild the route through one debounced path. The old route fades out and tears down before the new one starts. This matters: a second tap on already-tapped processes captures only silence, so routes must never overlap. The new route settles briefly, then fades in. Toggling sounds like a crossfade, not a glitch.

### The real-time path

The render callback runs about 100 times per second on an audio thread. The hot path does as close to nothing as possible:

- **Zero-copy first.** Planar tap buffers go to the mixer by pointer. No copy. Planar output buffers receive the render directly. No scratch buffer.
- **vDSP for the rest.** Interleaving and deinterleaving are single SIMD calls (`vDSP_ctoz` / `vDSP_ztoc`). Matching layouts use `memcpy`. Worst case is two vDSP calls per cycle.
- **Real-time hygiene.** No allocations. No locks. No Objective-C weak loads. The IO proc captures the mixer strongly, and scratch buffers are preallocated for the maximum slice size.
- **Graceful degradation.** Unknown buffer shapes fall back to a per-sample bridge. Render failures output silence, not garbage.

### Project layout

| Path | What it is |
|---|---|
| `Sources/SpotifyNativeSpatialCore` | UI-free render core: `AppleSpatialMixerRenderer`, the fixed spatial profile, the buffer bridge, output-kind inference |
| `Sources/SpotifyNativeSpatial` | The app: menu bar UI (MacControlCenterUI), process discovery, tap/aggregate lifecycle, device and sample-rate observers, CLI entry points |
| `Tests/SpotifyNativeSpatialCoreTests` | Buffer-bridge correctness, mixer configuration, profile invariants, and source-level guards on the render path |
| `tools/make_app_icon.sh` | Regenerates `Resources/AppIcon.icns` |

The tests include purity guards. These source-inspection tests fail if anyone adds post-processing or manual head-pose math. They also pin the routing invariants: drift compensation stays on, routes never overlap. The hands-off render path is enforced, not promised.

## Limitations

- The AirPods Spatial Audio menu may not list the original app as supported content. That app is still its own CoreAudio client. What you hear is the helper-rendered feed.
- CoreAudio exposes process-level audio, not browser tabs. Spacify can spatialize a browser, not one tab.
- The app is not notarized. The install script approves it locally. Installing by hand means right-clicking the app and choosing Open the first time.
