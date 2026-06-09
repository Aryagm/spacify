APP_NAME := SpotifyNativeSpatial
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
EXECUTABLE := .build/release/$(APP_NAME)
BUNDLED_EXECUTABLE := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

.PHONY: build app run run-head run-spotify run-spotify-head list inspect-cef run-cef-avf run-cef-avf-logged sample-audio-stack native-probe run-native-probe prepare-probe-copy run-probe-copy run-probe-component run-probe-component-unsafe run-probe-unit run-probe-object run-probe-audio run-probe-audio-unsafe inspect-probe-log clean

build:
	swift build -c release

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp "$(EXECUTABLE)" "$(BUNDLED_EXECUTABLE)"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

run: app
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	/usr/bin/open -n "$(APP_BUNDLE)"

run-head: app
	@echo "Enabling CoreMotion headphone tracking when the current output route supports it."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	/usr/bin/open -n "$(APP_BUNDLE)" --args --head-tracking

run-spotify: app
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	"$(BUNDLED_EXECUTABLE)" --render-spotify

run-spotify-head: app
	@echo "Direct Spotify diagnostics do not start CoreMotion. Use make run-head for menu-bar head tracking."
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	"$(BUNDLED_EXECUTABLE)" --render-spotify --head-tracking

list: app
	"$(BUNDLED_EXECUTABLE)" --list

inspect-cef:
	tools/inspect_spotify_cef.sh

run-cef-avf:
	tools/launch_spotify_avfoundation.sh

run-cef-avf-logged:
	tools/run_spotify_avfoundation_logged.sh

sample-audio-stack:
	tools/sample_spotify_audio_stack.sh

native-probe:
	tools/build_native_audio_probe.sh
	tools/build_probe_launcher.sh

run-native-probe:
	tools/run_spotify_with_native_probe.sh

prepare-probe-copy:
	tools/prepare_spotify_probe_copy.sh

run-probe-copy:
	tools/run_spotify_probe_copy.sh

run-probe-component:
	@echo "Disabled: the AudioComponentInstanceNew probe recurses inside Spotify and can close the app when playback starts."
	@echo "Use make run-probe-unit next. The component probe already confirmed Spotify creates Apple's default output AudioUnit."
	@exit 2

run-probe-component-unsafe:
	ALLOW_UNSAFE_COMPONENT_PROBE=1 PROBE_MODE=component tools/run_spotify_probe_copy.sh

run-probe-unit:
	PROBE_MODE=unit tools/run_spotify_probe_copy.sh

run-probe-object:
	PROBE_MODE=object tools/run_spotify_probe_copy.sh

run-probe-audio:
	@echo "Disabled: the combined audio probe includes the unstable component interpose."
	@echo "Use make run-probe-unit or make run-probe-object instead."
	@exit 2

run-probe-audio-unsafe:
	ALLOW_UNSAFE_COMPONENT_PROBE=1 PROBE_MODE=audio tools/run_spotify_probe_copy.sh

inspect-probe-log:
	tools/inspect_latest_native_probe_log.sh

clean:
	rm -rf .build "$(BUILD_DIR)"
