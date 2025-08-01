#!/bin/bash

# Install Development Dependencies Script
# This script installs all necessary tools for Tray Lang development

set -e

echo "🔧 Installing Development Dependencies for Tray Lang"

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

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    print_error "Homebrew is not installed. Please install it first:"
    echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

print_status "Installing Xcode Command Line Tools..."
xcode-select --install || true

print_status "Installing create-dmg for DMG creation..."
brew install create-dmg

print_status "Installing SwiftLint for code formatting..."
brew install swiftlint

print_status "Installing SwiftGen for asset generation..."
brew install swiftgen

print_status "Installing fastlane for deployment automation..."
brew install fastlane

print_status "Installing GitHub CLI for repository management..."
brew install gh

print_status "Installing additional development tools..."
brew install git-lfs
brew install pre-commit

print_status "Setting up pre-commit hooks..."
pre-commit install

print_status "All dependencies installed successfully!"
echo ""
echo "📋 Installed tools:"
echo "   - Xcode Command Line Tools"
echo "   - create-dmg (for DMG creation)"
echo "   - SwiftLint (code formatting)"
echo "   - SwiftGen (asset generation)"
echo "   - fastlane (deployment automation)"
echo "   - GitHub CLI (repository management)"
echo "   - git-lfs (large file handling)"
echo "   - pre-commit (code quality hooks)"
echo ""
echo "🚀 You're ready to develop Tray Lang!" 