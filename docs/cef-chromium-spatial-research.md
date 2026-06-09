# CEF / Chromium Spatial Audio Research

Date: 2026-05-05

## Goal

Force Apple/AirPods Spatial Audio in the native Spotify desktop app without moving playback to Safari or the Spotify web player.

## Current Conclusion

The custom CEF path is real, but it is not the first thing to build.

Spotify's bundled Chromium Embedded Framework already contains Chromium's macOS `AVFoundationOutputStream` path and the `MacAVFoundationPlayback` feature gate. The first practical experiment is to relaunch Spotify with:

```sh
--enable-features=MacAVFoundationPlayback
```

If that makes the AirPods Spatial Audio menu switch from unavailable/off to Fixed/Head Tracked while Spotify is playing, we do not need a custom CEF build.

If it does not work, a custom CEF build is only useful if Spotify's music playback actually uses Chromium's `media::AudioOutputStream` path. The current evidence suggests Spotify's main/native playback stack may own the music renderer, which would make CEF patching irrelevant for tracks even though it could affect web/audio elements inside the embedded UI.

## Evidence

### Upstream Chromium Has The Needed Backend

Chromium added `AVFoundationOutputStream` for macOS. Its header says the stream exists to use AVFoundation instead of AUHAL and to make AirPods Spatial Audio modes available in Control Center / the menu bar.

Source:
- https://chromium.googlesource.com/chromium/src/+/HEAD/media/audio/mac/avfoundation_output_stream.h

Chromium's `AudioManagerMac` selects `AVFoundationOutputStream` when `features::kMacAVFoundationPlayback` is enabled and the stream latency tag is `AudioLatency::Type::kPlayback`.

Source:
- https://chromium.googlesource.com/chromium/src/media/+/master/audio/mac/audio_manager_mac.cc

The feature is disabled by default in Chromium source:

```cpp
BASE_FEATURE(kMacAVFoundationPlayback, base::FEATURE_DISABLED_BY_DEFAULT);
```

Source:
- https://chromium.googlesource.com/chromium/src/+/refs/heads/main/media/audio/audio_features.cc

### Installed Spotify Already Contains That Code

Local Spotify install inspected:

```text
/Applications/Spotify.app
CFBundleIdentifier: com.spotify.client
CFBundleShortVersionString: 1.2.88.483
CFBundleVersion: 1.2.88.483
```

Spotify helper process args show:

```text
Chrome/146.0.7680.179 Spotify/1.2.88.483
```

`otool -L` on Spotify's CEF framework reports compatibility version:

```text
1460.0.10
```

`strings` on Spotify's bundled CEF framework finds:

```text
MacAVFoundationPlayback
com.chromium.media.AVFoundationOutputStream
Failed to create AVSampleBufferAudioRenderer.
AVSampleBufferAudioRenderer failed:
Required for Spatial Audio (AirPods head tracking).
```

This means "patch Chromium to add AVFoundation spatial output" is probably already done in Spotify's CEF. The unknown is whether Spotify enables it and whether music playback goes through it.

### Spotify Music Playback May Not Be A Chromium Media Stream

Our process tap diagnostic currently sees Spotify's main process as the CoreAudio owner:

```text
Spotify CoreAudio processes:
- pid 669 Spotify [idle] com.spotify.client
```

The main Spotify binary contains many native playback-core strings, including:

```text
core-playback-setup
core-playback-platform
playback_esperanto.proto
SPTPlaybackSettingsEsperanto
```

That does not prove the stream bypasses Chromium, because CEF is loaded into the main process. It does mean a CEF patch is not automatically sufficient. The proof has to be the AirPods menu or an observable `AVFoundationOutputStream` creation while a Spotify track is playing.

### Replacing CEF Has Signing And Compatibility Risks

Spotify is signed and hardened:

```text
Identifier=com.spotify.client
flags=0x10000(runtime)
Authority=Developer ID Application: Spotify (2FNC3A47ZF)
TeamIdentifier=2FNC3A47ZF
Sealed Resources version=2 files=185
```

Replacing `Chromium Embedded Framework.framework` will break the existing signature and require re-signing a copied app bundle. That may break updater behavior, keychain access assumptions, DRM/CDM behavior, crash reporting, or library validation expectations.

## Experiment Plan

### Experiment 1: Runtime Feature Flag

Use `tools/launch_spotify_avfoundation.sh`.

It quits Spotify, relaunches it with Chromium's AVFoundation playback feature enabled, and prints the resulting Spotify process tree.

While Spotify is playing a track on AirPods:

1. Open Control Center.
2. Open the AirPods audio menu.
3. Check whether Spatial Audio / Spatialize Stereo offers Off, Fixed, and Head Tracked.

Outcome interpretation:

- Works: stop here. Runtime flag is the best solution.
- Does not work and process args do not contain the feature: Spotify may strip or not forward CEF flags.
- Does not work but process args contain the feature: likely Spotify music playback is not using Chromium's playback `AudioOutputStream`, or the stream is not tagged as `kPlayback`.

Result from 2026-05-05 local run:

```text
/Applications/Spotify.app/Contents/MacOS/Spotify --enable-features=MacAVFoundationPlayback ...
Spotify Helper ... --enable-features=MacAVFoundationPlayback ...
```

The flag propagated to the main Spotify process and CEF helper processes. After starting playback through AppleScript, the CoreAudio process tap still reported:

```text
Spotify CoreAudio processes:
- pid 72524 Spotify [active] com.spotify.client
```

This means Spotify accepted the Chromium feature flag at process launch. It does not prove the music stream used `AVFoundationOutputStream`; the AirPods Control Center menu must be checked while playback is active.

Result from user run:

```text
Initial AVFoundation/AUHAL log scan:
```

No lines matched `AVFoundationOutputStream`, `AVSampleBufferAudioRenderer`, `Creating AVFoundationOutputStream`, or `AUHALStream` after playback.

Follow-up inspection showed the log only contained CEF crash-reporting startup lines. Spotify's CEF build accepted the feature flag but did not emit useful Chromium audio verbose logs.

### Experiment 2: Confirm The Renderer Owner

Use `tools/inspect_spotify_cef.sh` while a Spotify track is actively playing.

For a narrower Chromium-stream diagnostic, use:

```sh
make run-cef-avf-logged
```

This launches Spotify's executable directly, captures stderr to `logs/spotify-avfoundation-*.log`, and prints a grep command for `AVFoundationOutputStream`, `AVSampleBufferAudioRenderer`, and `AUHALStream`.

If Chromium logs are silent, sample the active process while a track is playing:

```sh
make sample-audio-stack
```

Local sample result from 2026-05-05:

```text
Thread: CoreAudioDriver Thread
Thread: com.apple.audio.IOThread.client
Thread: Media Mixer Renderer Thread
AudioConverterFillComplexBufferRealtimeSafe
```

Those threads and stacks are in the main Spotify process. This strongly supports the native Spotify audio-renderer path rather than a CEF helper using Chromium's `AVFoundationOutputStream`.

Useful signals:

- `make list` still showing the main Spotify process as active supports the "native playback owner" theory.
- Helper processes emitting CoreAudio output would support the "Chromium media pipeline" theory.
- The AirPods menu is the real test because Chromium release logs may not expose `DVLOG` messages.
- A log hit for `AVFoundationOutputStream` during music playback supports the Chromium backend path.
- Only `AUHALStream` hits, or no Chromium audio stream hits, supports the native Spotify playback path.

### Experiment 3: Only Then Consider A Custom CEF Build

If the feature flag is blocked or ignored, the smallest CEF patch would be one of:

1. Change `kMacAVFoundationPlayback` to enabled-by-default.
2. Remove the feature check around `AVFoundationOutputStream` creation in `AudioManagerMac`.
3. Broaden the condition if Spotify's stream is not tagged `AudioLatency::Type::kPlayback`.

The build target would need to match Spotify's installed CEF/Chromium line:

```text
CEF: 146.0.10
Chromium: 146.0.7680.179
```

This is high effort. It requires a Chromium/CEF checkout, macOS arm64 build tooling, a copied Spotify app bundle, replacing the framework, and ad-hoc re-signing. Even if it launches, Spotify updates can overwrite it.

## Recommendation

Do not start by recompiling CEF. Based on the runtime flag and sampling results, a CEF rebuild is unlikely to affect normal Spotify track playback unless Spotify's native renderer can be made to route through Chromium's `AudioOutputStream`.

The next research target should be Spotify's native audio renderer, specifically the code paths suggested by local binary strings:

```text
AVFoundationRenderer
AudioUnit2Renderer
CoreAudioRenderer
CoreAudioDriver
Media Mixer Renderer Thread
```

Additional native strings found:

```text
AudioRendererImpl %p format [%s, %d Hz] driver [stream type %s content type %s]
com.spotify.avfoundationrenderer
com.spotify.audio.sample-buffer-audio-renderer
SPTDefaultAVFoundationFactory
SPTAVFoundationFactory
SPTAVFoundationRendererObserver
external/spotify/shared/audio/driver_impl/src/core_audio_driver.cpp
AudioUnitSetProperty StreamFormat
AudioUnitSetProperty SetRenderCallback
AudioUnitSetProperty ChannelLayout
AudioUnitInitialize
AudioOutputUnitStop
AudioUnitUninitialize
CoreAudioDriver Thread
```

Spotify's hardened-runtime entitlements include:

```text
com.apple.security.cs.disable-library-validation
com.apple.security.cs.allow-jit
com.apple.security.cs.allow-unsigned-executable-memory
com.apple.security.cs.disable-executable-page-protection
```

It does not expose `com.apple.security.cs.allow-dyld-environment-variables`, so `DYLD_INSERT_LIBRARIES` may be ignored for the official signed app. Use `make run-native-probe` to test whether interposition is possible without copying/re-signing Spotify.

If the official app blocks interposition, use:

```sh
make run-probe-copy
```

That copies Spotify to `build/SpotifyNativeProbe.app`, ad-hoc re-signs the copy with local instrumentation entitlements, and launches the copy with `libSpotifyNativeAudioProbe.dylib`. It does not modify `/Applications/Spotify.app`.

The probe-copy launch requires a local launcher instead of `/usr/bin/nohup`: system binaries strip DYLD injection, and normal background shell launch can let the app receive terminal hangup. The local `spotify_probe_launcher` ignores SIGHUP, detaches, and then `exec`s the copied Spotify binary with the probe environment intact.

After the copied app is running, click Play in the instrumented Spotify window and inspect:

```sh
make inspect-probe-log
```

Do not use AppleScript for this copy. It tends to target the official Spotify app or disrupt the copied app's process registration. The probe copy uses `com.spotify.client.probe` by default so it does not collide with the official app's runtime state. Using `PROBE_BUNDLE_ID=com.spotify.client` can reuse the normal cache, but in local testing that crashed under injection.

The native probe now defaults to `PROBE_MODE=load` because the first all-in-one interpose attempt crashed Spotify shortly after playback started. The component-only hook reached Spotify's native audio path and showed repeated creation attempts for Apple's default output AudioUnit:

```text
AudioComponentInstanceNew begin type=auou subtype=def  manufacturer=appl
```

That hook recurses before `AudioComponentInstanceNew` returns, so it can close Spotify as soon as playback starts. Continue with the lower-level hooks:

```sh
make run-probe-unit
make run-probe-object
```
