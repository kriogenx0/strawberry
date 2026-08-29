PROJECT := Strawberry.xcodeproj
SCHEME := Strawberry
CONFIGURATION := Debug
BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/$(SCHEME).app
RELEASE_APP := $(BUILD_DIR)/Build/Products/Release/$(SCHEME).app

.PHONY: dev build test open publish install clean

dev: build open

build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		build

test:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		-destination 'platform=macOS' \
		test

# Kill any running instance, then launch the freshly built app.
open:
	-pkill -x "$(SCHEME)" 2>/dev/null || true
	@sleep 0.5
	open "$(APP)"

# Production (Release) build.
publish:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		build

# Production build, then install into /Applications.
install: publish
	rm -rf "/Applications/$(SCHEME).app"
	ditto "$(RELEASE_APP)" "/Applications/$(SCHEME).app"
	@echo "Installed /Applications/$(SCHEME).app"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(BUILD_DIR) clean
	rm -rf $(BUILD_DIR)
