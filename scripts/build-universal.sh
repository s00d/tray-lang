#!/bin/bash

# Build Universal macOS App Script
# This script builds a universal binary (Intel + Apple Silicon) for Tray Lang

set -e

echo "🚀 Building Universal macOS App for Tray Lang"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "tray-lang.xcodeproj/project.pbxproj" ]; then
    print_error "Please run this script from the project root directory"
    exit 1
fi

# Create build directory
BUILD_DIR="build/Release"
mkdir -p "$BUILD_DIR"

print_status "Cleaning previous builds..."
xcodebuild clean -project tray-lang.xcodeproj -scheme tray-lang

print_status "Building for Intel (x86_64)..."
xcodebuild -project tray-lang.xcodeproj -scheme tray-lang -configuration Release -destination 'platform=macOS,arch=x86_64' build

# Copy Intel build
cp -r "$BUILD_DIR/tray-lang.app" "$BUILD_DIR/tray-lang-intel.app"

print_status "Building for Apple Silicon (arm64)..."
xcodebuild -project tray-lang.xcodeproj -scheme tray-lang -configuration Release -destination 'platform=macOS,arch=arm64' build

# Copy Apple Silicon build
cp -r "$BUILD_DIR/tray-lang.app" "$BUILD_DIR/tray-lang-arm64.app"

print_status "Creating universal binary..."
# Create universal binary using lipo
lipo -create "$BUILD_DIR/tray-lang-intel.app/Contents/MacOS/tray-lang" "$BUILD_DIR/tray-lang-arm64.app/Contents/MacOS/tray-lang" -output "$BUILD_DIR/tray-lang-universal"

# Copy the universal binary to the Intel app
cp "$BUILD_DIR/tray-lang-universal" "$BUILD_DIR/tray-lang-intel.app/Contents/MacOS/tray-lang"

# Create final universal app
cp -r "$BUILD_DIR/tray-lang-intel.app" "$BUILD_DIR/tray-lang-universal.app"

print_status "Creating DMG..."
# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    print_warning "create-dmg not found. Installing via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install create-dmg
    else
        print_error "Homebrew not found. Please install create-dmg manually:"
        print_error "brew install create-dmg"
        exit 1
    fi
fi

# Create DMG
create-dmg \
  --volname "Tray Lang" \
  --window-pos 200 120 \
  --window-size 600 300 \
  --icon-size 100 \
  --icon "tray-lang-universal.app" 175 120 \
  --hide-extension "tray-lang-universal.app" \
  --app-drop-link 425 120 \
  "$BUILD_DIR/Tray-Lang-Universal.dmg" \
  "$BUILD_DIR/"

print_status "Build completed successfully!"
echo ""
echo "📦 Build artifacts:"
echo "   - Universal App: $BUILD_DIR/tray-lang-universal.app"
echo "   - DMG: $BUILD_DIR/Tray-Lang-Universal.dmg"
echo ""
echo "🔍 To verify the universal binary:"
echo "   file $BUILD_DIR/tray-lang-universal.app/Contents/MacOS/tray-lang"
echo ""
echo "✅ The app should show 'Mach-O universal binary with 2 architectures'" 