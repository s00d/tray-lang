# Makefile for Tray Lang Development
# Provides convenient commands for common development tasks

.PHONY: help build test test-ui clean install-deps build-universal create-dmg release

# Default target
help:
	@echo "Tray Lang Development Commands:"
	@echo ""
	@echo "  make build              - Build the app in Debug configuration"
	@echo "  make build-release      - Build the app in Release configuration"
	@echo "  make test               - Run unit tests (log: build/test.log)"
	@echo "  make test-ui            - Run UI tests (launches the app)"
	@echo "  make clean              - Clean build artifacts"
	@echo "  make install-deps       - Install development dependencies"
	@echo "  make build-universal    - Build universal binary (Intel + Apple Silicon)"
	@echo "  make create-dmg         - Create DMG installer"
	@echo "  make release            - Complete release process"
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

# Install dependencies
install-deps:
	./scripts/install-dependencies.sh

# Build universal binary
build-universal:
	./scripts/build-universal.sh

# Create DMG
create-dmg:
	@if [ ! -f "build/Release/tray-lang-universal.app" ]; then \
		echo "Universal app not found. Building first..."; \
		$(MAKE) build-universal; \
	fi
	@if ! command -v create-dmg &> /dev/null; then \
		echo "Installing create-dmg..."; \
		brew install create-dmg; \
	fi
	create-dmg \
		--volname "Tray Lang" \
		--window-pos 200 120 \
		--window-size 600 300 \
		--icon-size 100 \
		--icon "tray-lang-universal.app" 175 120 \
		--hide-extension "tray-lang-universal.app" \
		--app-drop-link 425 120 \
		"build/Release/Tray-Lang-Universal.dmg" \
		"build/Release/"

# Release process
release:
	@echo "Starting release process..."
	$(MAKE) clean
	$(MAKE) test
	$(MAKE) build-universal
	$(MAKE) create-dmg
	@echo "Release artifacts created in build/Release/"

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
	$(MAKE) build
	open build/Debug/tray-lang.app

# Git helpers
git-setup:
	git config core.hooksPath .git/hooks
	pre-commit install

# Documentation
docs:
	@echo "Generating documentation..."
	@echo "Documentation files:"
	@echo "  - README.md"
	@echo "  - CONTRIBUTING.md"
	@echo "  - CHANGELOG.md"
	@echo "  - LICENSE" 