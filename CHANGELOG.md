# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-08-01

### Added
- Hidden mode application launch (no main window on startup)
- Automatic accessibility permissions check on startup
- Application restart functionality after granting permissions
- Background mode operation with tray icon only
- Automatic window opening for editors and dialogs
- Enhanced installation script with automatic /Applications installation
- Universal binary support for both Intel and Apple Silicon Macs
- Comprehensive CI/CD with GitHub Actions
- Automatic DMG creation with README and signing script
- Version-based release naming

### Changed
- Application now launches in background mode with tray icon only
- Main window is created only when needed (Settings, Editors, About)
- Improved user experience with automatic window management
- Enhanced installation process with one-click setup
- Updated release process with automatic version detection

### Fixed
- Main window no longer appears on application startup
- Proper window management for all menu items
- Automatic accessibility permissions handling
- Streamlined installation and signing process
- Improved user interface consistency

## [1.0.0] - 2025-08-01

### Added
- Initial release of Tray Lang
- Automatic keyboard layout switching
- Customizable hotkeys
- Multi-language character mapping support
- Tray icon functionality
- Auto-launch capability
- Accessibility permissions handling
- Modern SwiftUI interface
- Support for 16+ language pairs
- Real-time hotkey capture
- Symbol mapping editor
- About window with GitHub link
- GitHub Actions workflows for CI/CD
- Universal binary support (Intel + Apple Silicon)
- Comprehensive documentation
- Contributing guidelines
- AppleScript-based text retrieval and replacement
- Robust clipboard management
- UserNotifications framework integration

### Changed
- Updated character mappings from transliteration to actual keyboard layouts
- Improved UI design and user experience
- Enhanced error handling and logging
- Refactored from multiple manager classes to single TrayLangManager
- Improved character mapping logic

### Fixed
- Hotkey capture issues
- Window management problems
- Accessibility permission handling
- Various UI and functionality issues
- Compiler warnings and deprecated API usage
- Text retrieval reliability in different applications
- Clipboard restoration after operations

### Supported Languages
- Russian ↔ English
- German ↔ English
- French ↔ English
- Spanish ↔ English
- Italian ↔ English
- Portuguese ↔ English
- Swedish ↔ English
- Norwegian ↔ English
- Danish ↔ English
- Finnish ↔ English
- Polish ↔ English
- Czech ↔ English
- Hungarian ↔ English
- Turkish ↔ English
- Greek ↔ English
- Cyrillic ↔ English



---

## Version History

- **1.1.0**: Enhanced release with hidden mode launch, automatic permissions handling, and improved installation process
- **1.0.0**: First stable release with full feature set, universal binary support, and comprehensive CI/CD

## Release Notes

### Version 1.1.0
Enhanced release focusing on user experience and installation simplicity. The application now launches in true background mode with improved accessibility handling and streamlined installation process.

Key improvements:
- Hidden mode launch (no main window on startup)
- Automatic accessibility permissions check
- One-click installation with automatic signing
- Background operation with tray icon only
- Automatic window management for all features
- Enhanced CI/CD with version-based releases
- Universal binary support
- Comprehensive installation documentation

### Version 1.0.0
This is the first stable release of Tray Lang. The application provides a complete solution for automatic keyboard layout switching with support for multiple languages and customizable character mappings.

Key features:
- Modern SwiftUI interface
- Comprehensive language support
- Secure accessibility permissions
- Tray-based operation
- Auto-launch capability
- Universal binary (Intel + Apple Silicon)
- AppleScript-based text operations
- Robust clipboard management
- GitHub Actions CI/CD
- Comprehensive documentation

 
