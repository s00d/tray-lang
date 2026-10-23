# Makefile for Tray Lang Development
# Provides convenient commands for common development tasks

.PHONY: help build test test-ui clean build-universal create-dmg install release

# Default target
help:
	@echo "Tray Lang Development Commands:"
	@echo ""
	@echo "  make build              - Build the app in Debug configuration"
	@echo "  make build-release      - Build the app in Release configuration"
	@echo "  make test               - Run unit tests (log: build/test.log)"
	@echo "  make test-ui            - Run UI tests (launches the app)"
	@echo "  make clean              - Clean build artifacts"
	@echo "  make build-universal    - Universal Release build, Developer ID signed"
	@echo "  make create-dmg         - DMG from the universal build (not notarized)"
	@echo "  make install            - Replace /Applications copy with a fresh build and restart"
	@echo "  make release            - How to publish a release (GitHub workflow)"
	@echo "  make lint               - Run SwiftLint"
	@echo "  make format             - Format code with SwiftLint"
	@echo ""

# Build targets
build:
	xcodebuild -project tray-lang.xcodeproj -scheme tray-lang -configuration Debug build
	@echo ""
	@echo "✅ Build completed successfully!"
	@BUILD_DIR=$$(xcodebuild -project tray-lang.xcodeproj -scheme tray-lang -configuration Debug -showBuildSettings 2>/dev/null | grep "^[[:space:]]*BUILT_PRODUCTS_DIR[[:space:]]*=" | head -1 | sed 's/.*=[[:space:]]*//' | xargs); \
	APP_NAME=$$(xcodebuild -project tray-lang.xcodeproj -scheme tray-lang -configuration Debug -showBuildSettings 2>/dev/null | grep "^[[:space:]]*PRODUCT_NAME[[:space:]]*=" | head -1 | sed 's/.*=[[:space:]]*//' | xargs); \
	if [ -n "$$BUILD_DIR" ] && [ -n "$$APP_NAME" ]; then \
		APP_PATH="$$BUILD_DIR/$$APP_NAME.app"; \
		if [ -d "$$APP_PATH" ]; then \
			echo "📦 Application built at: $$APP_PATH"; \
		else \
			echo "📦 Application built at: build/Debug/tray-lang.app"; \
		fi; \
	else \
		echo "📦 Application built at: build/Debug/tray-lang.app"; \
	fi

build-release:
	xcodebuild -project tray-lang.xcodeproj -scheme tray-lang -configuration Release build
	@echo ""
	@echo "✅ Release build completed successfully!"
	@BUILD_DIR=$$(xcodebuild -project tray-lang.xcodeproj -scheme tray-lang -configuration Release -showBuildSettings 2>/dev/null | grep "^[[:space:]]*BUILT_PRODUCTS_DIR[[:space:]]*=" | head -1 | sed 's/.*=[[:space:]]*//' | xargs); \
	APP_NAME=$$(xcodebuild -project tray-lang.xcodeproj -scheme tray-lang -configuration Release -showBuildSettings 2>/dev/null | grep "^[[:space:]]*PRODUCT_NAME[[:space:]]*=" | head -1 | sed 's/.*=[[:space:]]*//' | xargs); \
	if [ -n "$$BUILD_DIR" ] && [ -n "$$APP_NAME" ]; then \
		APP_PATH="$$BUILD_DIR/$$APP_NAME.app"; \
		if [ -d "$$APP_PATH" ]; then \
			echo "📦 Application built at: $$APP_PATH"; \
		else \
			echo "📦 Application built at: build/Release/tray-lang.app"; \
		fi; \
	else \
		echo "📦 Application built at: build/Release/tray-lang.app"; \
	fi

# Test targets (ad-hoc signed: no developer certificate needed; logs go to build/test.log)
TEST_FLAGS = -project tray-lang.xcodeproj -scheme tray-lang -destination 'platform=macOS' \
	CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=

test:
	@mkdir -p build
	xcodebuild test $(TEST_FLAGS) -only-testing:tray-langTests > build/test.log 2>&1; \
	status=$$?; grep -E "Test run with|tests? (passed|failed)|✘|error:" build/test.log; echo "Full log: build/test.log"; exit $$status

# UI tests launch the real app and need Accessibility for the test runner.
test-ui:
	@mkdir -p build
	xcodebuild test $(TEST_FLAGS) -only-testing:tray-langUITests > build/test-ui.log 2>&1; \
	status=$$?; grep -E "Executed|error:" build/test-ui.log; echo "Full log: build/test-ui.log"; exit $$status

# Clean target
clean:
	xcodebuild clean -project tray-lang.xcodeproj -scheme tray-lang
	rm -rf build/
	rm -rf DerivedData/

# Universal (Apple Silicon + Intel) Release build signed with the local Developer ID certificate.
# Notarization and the GitHub release are done by the "Release" workflow.
UNIVERSAL_APP = build/universal/Build/Products/Release/tray-lang.app
TEAM ?= R6VC7JTLE8

build-universal:
	@mkdir -p build
	xcodebuild build -project tray-lang.xcodeproj -scheme tray-lang -configuration Release \
		-destination 'generic/platform=macOS' -derivedDataPath build/universal \
		ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=$(TEAM) PROVISIONING_PROFILE_SPECIFIER= \
		OTHER_CODE_SIGN_FLAGS=--timestamp > build/universal.log 2>&1 || { grep error: build/universal.log; exit 1; }
	@lipo -archs $(UNIVERSAL_APP)/Contents/MacOS/tray-lang
	@codesign --verify --strict $(UNIVERSAL_APP) && echo "Built and signed: $(UNIVERSAL_APP)"

create-dmg: build-universal
	@rm -rf build/dmg && mkdir -p build/dmg
	ditto $(UNIVERSAL_APP) build/dmg/tray-lang-universal.app
	cp README.md build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Tray Lang" -srcfolder build/dmg -ov -format UDZO build/Tray-Lang-Universal.dmg
	@rm -rf build/dmg

# Replace the copy in /Applications with a fresh universal build and restart it.
install: build-universal
	-osascript -e 'tell application id "os.s00d.tray-lang" to quit'
	@sleep 1
	rm -rf /Applications/tray-lang-universal.app
	ditto $(UNIVERSAL_APP) /Applications/tray-lang-universal.app
	open /Applications/tray-lang-universal.app

release:
	@echo "Bump MARKETING_VERSION, push, then run the Release workflow:"
	@echo "  gh workflow run build.yml --ref main"

# Code quality
lint:
	@if ! command -v swiftlint &> /dev/null; then \
		echo "Installing SwiftLint..."; \
		brew install swiftlint; \
	fi
	swiftlint lint

format:
	@if ! command -v swiftlint &> /dev/null; then \
		echo "Installing SwiftLint..."; \
		brew install swiftlint; \
	fi
	swiftlint --fix

# Development helpers
open-project:
	open tray-lang.xcodeproj

run:
	xcodebuild build -project tray-lang.xcodeproj -scheme tray-lang -configuration Debug -derivedDataPath build/debug \
		CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= > build/debug.log 2>&1 || { grep error: build/debug.log; exit 1; }
	open build/debug/Build/Products/Debug/tray-lang.app --args -openSettings
