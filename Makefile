# Makefile for Tray Lang Development
# Provides convenient commands for common development tasks

.PHONY: help build test clean install-deps build-universal create-dmg release

# Default target
help:
	@echo "Tray Lang Development Commands:"
	@echo ""
	@echo "  make build              - Build the app in Debug configuration"
	@echo "  make build-release      - Build the app in Release configuration"
	@echo "  make test               - Run unit and UI tests"
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

build-release:
	xcodebuild -project tray-lang.xcodeproj -scheme tray-lang -configuration Release build

# Test targets
test:
	xcodebuild test -project tray-lang.xcodeproj -scheme tray-lang -destination 'platform=macOS'

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