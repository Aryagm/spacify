APP_NAME := Spacify
TARGET_NAME := SpotifyNativeSpatial
LEGACY_APP_NAME := SpotifyNativeSpatial
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
EXECUTABLE := .build/release/$(TARGET_NAME)
BUNDLED_EXECUTABLE := $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

.PHONY: build app run run-head run-spotify run-spotify-head list icon test clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	cp "$(EXECUTABLE)" "$(BUNDLED_EXECUTABLE)"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

run: app
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@pkill -x "$(LEGACY_APP_NAME)" 2>/dev/null || true
	/usr/bin/open -n "$(APP_BUNDLE)"

run-head: app
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@pkill -x "$(LEGACY_APP_NAME)" 2>/dev/null || true
	/usr/bin/open -n "$(APP_BUNDLE)" --args --head-tracking

run-spotify: app
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@pkill -x "$(LEGACY_APP_NAME)" 2>/dev/null || true
	"$(BUNDLED_EXECUTABLE)" --render-spotify

run-spotify-head: app
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@pkill -x "$(LEGACY_APP_NAME)" 2>/dev/null || true
	"$(BUNDLED_EXECUTABLE)" --render-spotify --head-tracking

list: app
	"$(BUNDLED_EXECUTABLE)" --list

icon:
	tools/make_app_icon.sh

clean:
	rm -rf .build "$(BUILD_DIR)"
