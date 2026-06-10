# Spacify

Menu bar app that reroutes selected app audio through a local Apple-spatialized monitor path, while every app stays its own native renderer.

This does **not** toggle Apple Spatial Audio inside another app such as Spotify — there is no public API that lets a helper process force Apple Spatial Audio onto another signed app. Instead, Spacify:

1. Finds CoreAudio process objects for visible apps.
2. Creates a macOS Core Audio Process Tap for the selected apps.
3. Mutes the selected apps while tapped, so they do not double-play.
4. Renders the tapped stereo stream to the current default output with Apple's `AUSpatialMixer`.
5. Optionally asks `AUSpatialMixer` to use AirPods native head tracking.
6. Bridges buffer layouts between the tap, mixer, and output device with zero-copy paths where layouts already match and Accelerate (vDSP) conversions where they do not.

## Requirements

- macOS 14.2 or newer for Core Audio Process Taps.
- Xcode command line tools.
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

Click the waveform icon in the macOS menu bar, then use the switches to spatialize any listed app. The helper recreates one shared process tap for all selected apps.

The Head Tracking switch uses AudioToolbox's native `kAudioUnitProperty_SpatialMixerEnableHeadTracking` property. The app does not read AirPods motion data, calculate yaw/pitch/roll, or tune the audio itself.

To launch with that switch already enabled regardless of the saved preference:

```sh
make run-head
```

For diagnostics without starting the tap, list CoreAudio-visible apps:

```sh
make list
```

For the terminal Spotify-only diagnostic path:

```sh
make run-spotify
make run-spotify-head
```

`make run` opens the generated `build/Spacify.app` bundle as a menu bar app and kills any previous helper instance first so duplicate menu bar icons do not accumulate.

## Behavior

- **Spatial profile.** The fixed spatial path is tuned as a clean music profile: Apple's `UseOutputType` spatialization, stereo input kept as an ambience bed, the mixer's default reverb wetness disabled, and playback rate locked at 1.0. After Apple's mixer renders, the app only bridges the mixer's float stereo buffers to the CoreAudio output buffer layout — no EQ, gain, compression, limiting, reverb, widening, crossfeed, manual head-pose rotation, or other custom DSP.
- **Output device selection.** The spatial output type (headphones / built-in speakers / external speakers) is inferred from the default output device, with personalized HRTF in auto mode.
- **Device following.** If the default output device changes (for example AirPods connect or disconnect), active routing is rebuilt automatically for the new device.
- **Persistence.** The head-tracking preference and app selections are saved and restored across launches. If selected apps are running at launch, routing resumes automatically.

## Limitations

- The AirPods Spatial Audio setting may not present the original app itself as supported content, because that app remains a separate CoreAudio client and the helper outputs processed PCM. The working path is the helper-rendered spatial monitor feed.
- CoreAudio exposes process-level audio, not browser tab identity. The menu can spatialize Chrome/Brave/etc. process audio; it cannot reliably promise one arbitrary tab unless the browser maps that tab to a distinct CoreAudio process.
- The app bundle is ad-hoc signed by `make app`. Distributing it to other Macs requires Developer ID signing and notarization.
