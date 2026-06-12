# Spacify

<p align="center"><img src="Resources/Banner.png" alt="Spacify: spatial audio for any Mac app"></p>

<p align="center">
  <a href="https://github.com/Aryagm/spacify/releases/latest"><img src="https://img.shields.io/github/v/release/Aryagm/spacify" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14.2%2B-blue" alt="macOS 14.2+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

Spotify doesn't support Spatial Audio on the Mac. Neither does Chrome. Spacify fixes that.

Flip a switch in the menu bar and any app's audio plays through Apple's spatial audio engine, with AirPods head tracking. No EQ, no fake widening. Just Apple's own spatializer, pointed at apps that never supported it.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Aryagm/spacify/main/install.sh | sh
```

The app is open source and not notarized, so the script ([12 lines](install.sh)) approves it locally. Or install by hand: download from [Releases](https://github.com/Aryagm/spacify/releases), drop it in `/Applications`, right-click → Open.

Then click the earbuds icon in the menu bar, toggle an app, and listen. macOS will ask for System Audio Recording permission; that's the audio tap.

## Features

- **Any audio app.** Streaming clients, browsers, games, video calls. Several at once.
- **AirPods head tracking.** Toggles live, without stopping the music.
- **Tuned to your output.** Binaural HRTF on headphones, speaker profiles elsewhere.
- **Two renders.** Dry by default. Flip on Room Ambience for Apple's room modeling, closer to native Spatialize Stereo.
- **Follows your devices.** Routing rebuilds itself when AirPods connect or disconnect.
- **No double audio.** Originals are muted at the system level while routed.
- **Remembers your setup.** Selections and preferences survive restarts.

## How it works

There is no public API to turn on Spatial Audio inside another app, and macOS's built-in Spatialize Stereo doesn't engage for most non-Apple apps. So Spacify captures the app's audio with a Core Audio process tap (macOS 14.2+), mutes the original, and re-renders the stream through Apple's `AUSpatialMixer` with native head tracking. Same engine, one step downstream.

Details, including the zero-copy render path: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Build from source

```sh
make app    # build the .app bundle
make run    # launch the menu bar app
make test   # run the test suite
```

Requires macOS 14.2+ and the Xcode command line tools.

## Limitations

- You hear Spacify's re-render of the app, so the AirPods menu may not list the original app as supported content.
- Spatialization is per-app, not per-browser-tab.

## License

[MIT](LICENSE)
