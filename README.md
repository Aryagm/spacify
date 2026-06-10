# Spacify

<p align="center"><img src="Resources/Banner.png" alt="Spacify — spatial audio for any Mac app"></p>

**Spatial audio for any Mac app.** Spacify is a menu bar utility that takes the sound of any running app — Spotify, Chrome, a game, anything CoreAudio can see — and re-renders it through Apple's own spatial audio engine, with optional AirPods head tracking. Apps that were never built for Spatial Audio suddenly sound like they were.

## Install

One command downloads the latest release into `/Applications`, approves it on your Mac, and launches it:

```sh
curl -fsSL https://raw.githubusercontent.com/Aryagm/spacify/main/install.sh | sh
```

Spacify is open source and not notarized, so the script clears the Gatekeeper download quarantine and applies a local ad-hoc signature — that's the "approve" step. It's a dozen readable lines: [`install.sh`](install.sh). Prefer doing it by hand? Grab the zip from [Releases](https://github.com/Aryagm/spacify/releases), drop the app in `/Applications`, and right-click → Open the first time.

The release binary is universal (Apple silicon + Intel) and needs **macOS 14.2+**.

First run: click the earbuds icon in the menu bar, toggle an app, listen. macOS will ask for **System Audio Recording** permission the first time you spatialize something — that's the process tap.

## What it does

Flip the switch next to an app and its stereo audio is lifted out of its normal playback path and re-rendered by `AUSpatialMixer` — the same spatializer behind Apple's own Spatial Audio:

- **Any audio app.** If it shows up in CoreAudio, it can be spatialized: streaming clients, browsers, games, video calls. Select several at once and they share one tap.
- **Native AirPods head tracking.** One switch anchors the sound stage in front of you using the AirPods' own motion engine, and it toggles live — the music never stops. Spacify never touches the motion data itself.
- **Tuned to your output.** Headphones get the binaural HRTF render (personalized HRTF in auto mode where available); built-in and external speakers get Apple's matching speaker profiles.
- **Follows your devices.** Pop your AirPods in or out and active routing rebuilds itself on the new output. If a device renegotiates its sample rate mid-route, the route rebuilds at the new rate instead of drifting off-pitch.
- **Remembers your setup.** App selections and the head-tracking preference persist across launches; routing resumes on its own if the apps are running.
- **No double audio.** Tapped apps are muted at the system level while routed, so you only ever hear the spatialized feed.

What it deliberately does **not** do: EQ, gain, compression, limiting, reverb tweaks, stereo widening, crossfeed, or any custom DSP. What you hear is Apple's spatial render of the original stream — nothing else. A fixed "clean music" profile keeps the mixer honest: stereo stays an ambience bed, the mixer's default reverb is zeroed, playback rate is locked at 1.0. The single exception is a sub-second fade when a route starts or stops so toggling doesn't click; steady-state audio is never touched.

## Why it exists

There is no public API to force Apple Spatial Audio *inside* another signed app, and macOS's built-in Spatialize Stereo only engages for apps on supported playback paths — Spotify's Chromium audio stack, like most non-Apple apps, never qualifies. Spacify takes the route that does work: capture the app's audio at the CoreAudio process level, mute the original, and run the stream through Apple's spatializer in a helper process. Same engine, same head tracking — rendered one step downstream.

## Build from source

```sh
make app    # build the .app bundle
make run    # launch the menu bar app
```

Requires macOS 14.2+ (Core Audio process taps) and the Xcode command line tools. `make run-head` launches with head tracking pre-enabled regardless of the saved preference; `make dist` produces the universal release zip.

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

1. **Discovery.** `AudioProcessResolver` enumerates CoreAudio process objects, maps them back to their owning `.app` bundles (with cached metadata), and groups multi-process apps — a Chromium browser's many helpers appear as one menu entry.
2. **Capture.** Selected apps share one `CATapDescription(stereoMixdownOfProcesses:)` process tap with `muteBehavior = .mutedWhenTapped`, so the originals go silent while tapped.
3. **Routing.** A private aggregate device wraps the current default output and the tap (`kAudioAggregateDeviceTapAutoStartKey`), clocked by the output device, with the tap drift-compensated to that clock — apps producing at a different sample rate stay pitch-correct. An IO proc on a `userInteractive` dispatch queue drives the render at the aggregate's rate.
4. **Spatialization.** `AUSpatialMixer` is configured at route start: `UseOutputType` spatialization, ambience-bed source mode, output type inferred from the device, personalized HRTF in auto mode (macOS 13+). Head tracking (`kAudioUnitProperty_SpatialMixerEnableHeadTracking`) toggles on the live mixer — no route rebuild, no interruption.
5. **Delivery.** The mixer's planar float output is bridged to whatever buffer layout the device expects and written straight into the IO proc's output buffers.

Selection changes and device switches rebuild the route through one debounced path. The old route fades out and is fully torn down before its replacement starts — a second tap on already-tapped processes captures only silence, so routes must never overlap — and the new route holds a short settle window before fading in, so toggling sounds like a crossfade rather than a glitch.

### The real-time path

The render callback runs ~100× per second on an audio thread, so the hot path is built to do as close to nothing as possible:

- **Zero-copy first.** When the tap delivers planar stereo float, the mixer's pull callback hands the tap buffers to the mixer by pointer — no copy. When the output buffers are already planar, the mixer renders directly into them — no scratch buffer.
- **vDSP for the rest.** Where layouts genuinely differ (interleaved ↔ planar), conversion is a single SIMD `vDSP_ctoz`/`vDSP_ztoc` call; matching layouts use `memcpy`. The worst case per cycle is two vDSP calls.
- **Real-time hygiene.** No allocations, no locks, no Objective-C weak loads in the callback: the IO proc captures the mixer strongly (the proc is destroyed before the mixer is released), and scratch buffers are preallocated for the maximum slice size.
- **Graceful degradation.** Unexpected buffer shapes fall back to a generic per-sample bridge, and render failures output silence rather than garbage.

### Project layout

| Path | What it is |
|---|---|
| `Sources/SpotifyNativeSpatialCore` | UI-free render core: `AppleSpatialMixerRenderer`, the fixed spatial profile, the buffer bridge, output-kind inference |
| `Sources/SpotifyNativeSpatial` | The app: menu bar UI (MacControlCenterUI), process discovery, tap/aggregate lifecycle, device and sample-rate observers, CLI entry points |
| `Tests/SpotifyNativeSpatialCoreTests` | Buffer-bridge correctness (exact sample values), mixer configuration, profile invariants, and source-level guards on the render path |
| `tools/make_app_icon.sh` | Regenerates `Resources/AppIcon.icns` |

The test suite includes *purity guards* — source-inspection tests that fail if anyone reintroduces post-processing or manual head-pose math, and that pin the routing invariants (drift compensation on, no overlapping route replacement). The hands-off render path is enforced, not just promised.

## Limitations

- The AirPods Spatial Audio menu may not list the original app as supported content — that app is still its own CoreAudio client, and what you hear is the helper-rendered monitor feed.
- CoreAudio exposes process-level audio, not browser-tab identity. Spacify can spatialize a browser's audio, not one arbitrary tab.
- The app is not notarized. The install script approves it locally (quarantine removal + ad-hoc signature); installing by hand means right-clicking the app and choosing Open the first time.
