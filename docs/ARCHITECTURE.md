# Architecture

How Spacify routes and renders audio.

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

## The pipeline

1. **Discovery.** `AudioProcessResolver` lists CoreAudio process objects and maps them to their `.app` bundles. Multi-process apps group into one menu entry. A Chromium browser's many helpers show as one row.
2. **Capture.** Selected apps share one process tap (`CATapDescription(stereoMixdownOfProcesses:)`). The tap mutes the originals while it runs.
3. **Routing.** A private aggregate device wraps the default output and the tap. The output device is the clock. The tap is drift-compensated to that clock, so apps producing at a different sample rate stay pitch-correct. An IO proc on a `userInteractive` queue drives the render at the aggregate's rate.
4. **Spatialization.** `AUSpatialMixer` is configured at route start: `UseOutputType` spatialization, ambience-bed source mode, output type inferred from the device, personalized HRTF in auto mode (macOS 13+). Head tracking toggles on the live mixer. No rebuild. No interruption.
5. **Delivery.** The mixer's planar float output is bridged to the device's buffer layout and written straight into the IO proc's buffers.

## Route lifecycle

Selection changes and device switches rebuild the route through one debounced path. The old route fades out and tears down before the new one starts. This matters: a second tap on already-tapped processes captures only silence, so routes must never overlap. The new route settles briefly, then fades in. Toggling sounds like a crossfade, not a glitch.

Two observers keep routes valid. One watches the default output device and rebuilds when it changes. One watches the device's nominal sample rate and rebuilds if it renegotiates mid-route.

## The real-time path

The render callback runs about 100 times per second on an audio thread. The hot path does as close to nothing as possible:

- **Zero-copy first.** Planar tap buffers go to the mixer by pointer. No copy. Planar output buffers receive the render directly. No scratch buffer.
- **vDSP for the rest.** Interleaving and deinterleaving are single SIMD calls (`vDSP_ctoz` / `vDSP_ztoc`). Matching layouts use `memcpy`. Worst case is two vDSP calls per cycle.
- **Real-time hygiene.** No allocations. No locks. No Objective-C weak loads. The IO proc captures the mixer strongly, and scratch buffers are preallocated for the maximum slice size.
- **Graceful degradation.** Unknown buffer shapes fall back to a per-sample bridge. Render failures output silence, not garbage.

## No custom DSP

Spacify adds no processing of its own. No EQ, no compression, no widening, no crossfeed. The default profile keeps the mixer dry: stereo stays an ambience bed, reverb is zeroed, playback rate is locked at 1.0. The Room Ambience toggle switches to a second profile that engages the mixer's built-in room reverb, which is closer to Apple's native Spatialize Stereo character. Both profiles are Apple's engine end to end. The one exception is a sub-second fade when a route starts or stops, so toggling doesn't click.

The tests enforce this. Purity guards are source-inspection tests that fail if anyone adds post-processing or manual head-pose math. They also pin the routing invariants: drift compensation stays on, routes never overlap.

## Project layout

| Path | What it is |
|---|---|
| `Sources/SpotifyNativeSpatialCore` | UI-free render core: `AppleSpatialMixerRenderer`, the fixed spatial profile, the buffer bridge, output-kind inference |
| `Sources/SpotifyNativeSpatial` | The app: menu bar UI (MacControlCenterUI), process discovery, tap/aggregate lifecycle, device and sample-rate observers, CLI entry points |
| `Tests/SpotifyNativeSpatialCoreTests` | Buffer-bridge correctness, mixer configuration, profile invariants, and source-level guards on the render path |
| `tools/make_app_icon.sh` | Regenerates `Resources/AppIcon.icns` |
