# Contributing to Tray Lang

Thank you for your interest in contributing to Tray Lang! This document provides guidelines and information for contributors.

## Project Structure

### Overview

Tray Lang is a macOS application that converts text between different keyboard layouts. The project follows a modular architecture with clear separation of concerns.

### Directory Structure

```
tray-lang/
├── tray-lang.xcodeproj/          # Xcode project files
├── tray-lang/                    # Main application bundle
│   ├── tray_langApp.swift        # App entry point and AppDelegate
│   ├── Info.plist               # Application configuration
│   ├── tray_lang.entitlements   # App entitlements
│   └── Sources/                 # Source code organized by layer
│       ├── Core/                # Core business logic
│       ├── Managers/            # Feature-specific managers
│       ├── UI/                  # SwiftUI views
│       ├── Components/          # Reusable UI components
│       └── Utils/              # Utility classes and extensions
├── tray-langTests/              # Unit tests
├── tray-langUITests/            # UI tests
├── fastlane/                    # CI/CD configuration
├── scripts/                     # Build and deployment scripts
└── .github/                     # GitHub workflows
```

### Architecture Layers

#### 1. Core Layer (`Sources/Core/`)

**Purpose**: Core business logic and fundamental managers

**Components**:
- `AppCoordinator.swift` - Main application coordinator, orchestrates all components
- `AccessibilityManager.swift` - Handles accessibility permissions and status
- `HotKeyManager.swift` - Manages global hotkey monitoring and events
- `KeyboardLayoutManager.swift` - Manages keyboard layout detection and switching
- `TextTransformer.swift` - Handles text transformation between layouts
- `KeyboardMapping.swift` - Defines keyboard mapping data structures

#### 2. Managers Layer (`Sources/Managers/`)

**Purpose**: Feature-specific business logic

**Components**:
- `TextProcessingManager.swift` - Handles text selection, retrieval, and replacement
- `AutoLaunchManager.swift` - Manages application auto-launch functionality

#### 3. UI Layer (`Sources/UI/`)

**Purpose**: SwiftUI views for user interface

**Components**:
- `ContentView.swift` - Main application window content
- `TrayMenuView.swift` - System tray menu interface
- `HotKeyEditorView.swift` - Hotkey configuration interface
- `SymbolsEditorView.swift` - Character mapping editor
- `AboutView.swift` - Application information view

#### 4. Components Layer (`Sources/Components/`)

**Purpose**: Reusable UI components and system integration

**Components**:
- `WindowManager.swift` - Manages application windows and dock icon
- `NotificationManager.swift` - Handles system notifications and alerts

#### 5. Utils Layer (`Sources/Utils/`)

**Purpose**: Utility classes, data structures, and extensions

**Components**:
- `HotKey.swift` - Hotkey data structure and serialization
- `KeyUtils.swift` - Keyboard utility functions
- `KeyCodes.swift` - Keyboard code constants
- `TrayLangError.swift` - Application error types

### Key Design Patterns

#### 1. Coordinator Pattern
- `AppCoordinator` acts as the main coordinator
- Manages dependencies between components
- Handles application lifecycle and event routing

#### 2. Manager Pattern
- Each major feature has its own manager
- Managers handle specific business logic
- Clear separation of concerns

#### 3. ObservableObject Pattern
- Core managers implement `ObservableObject`
- Enables reactive UI updates
- Used for state management

#### 4. Notification Pattern
- Inter-component communication via `NotificationCenter`
- Loose coupling between components
- Event-driven architecture

### Data Flow

```
User Action → HotKeyManager → AppCoordinator → TextProcessingManager → TextTransformer → UI Update
```

### Key Features

#### 1. Text Processing
- **Selection**: Multiple methods for text selection (Accessibility API, AppleScript)
- **Transformation**: Character-by-character mapping between layouts
- **Replacement**: Smart text replacement with clipboard management

#### 2. Accessibility Integration
- **Permission Management**: Automatic permission requests
- **Status Monitoring**: Real-time accessibility status tracking
- **Fallback Mechanisms**: Multiple methods for text manipulation

#### 3. Hotkey System
- **Global Monitoring**: System-wide hotkey detection
- **Configuration**: User-customizable hotkeys
- **Persistence**: Hotkey settings saved to UserDefaults

#### 4. UI Components
- **Tray Integration**: System tray menu with popover
- **Modal Views**: Settings and configuration dialogs
- **Status Indicators**: Real-time status display

## Getting Started

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later
- Git

### Setting Up the Development Environment

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/tray-lang.git
   cd tray-lang
   ```
3. Open the project in Xcode:
   ```bash
   open tray-lang.xcodeproj
   ```
4. Build and run the project (⌘+R)

## Development Guidelines

### Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions small and focused
- Use SwiftUI best practices

### Architecture Principles

- **Single Responsibility**: Each class has one clear purpose
- **Dependency Injection**: Dependencies passed through constructors
- **Separation of Concerns**: UI, business logic, and data access separated
- **Testability**: Components designed for easy testing

### Testing Strategy

- **Unit Tests**: Test individual components in isolation
- **Integration Tests**: Test component interactions
- **UI Tests**: Test user workflows
- **Accessibility Tests**: Ensure accessibility compliance

## Making Changes

### Creating a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### Commit Messages

Use clear, descriptive commit messages following conventional commits:

```
feat: add new language support for French
fix: resolve hotkey capture issue
docs: update README with installation instructions
refactor: improve text processing performance
test: add unit tests for TextTransformer
```

### Pull Request Process

1. Ensure your code builds without errors
2. Run tests to ensure nothing is broken
3. Update documentation if needed
4. Create a pull request with a clear description
5. Wait for review and address any feedback

## Common Development Tasks

### Adding a New Language

1. Add language template to `SymbolsEditorView.swift`
2. Update `KeyboardMapping.swift` if needed
3. Test with various applications
4. Update documentation

### Modifying Text Processing

1. Update `TextProcessingManager.swift`
2. Test with different applications
3. Ensure fallback mechanisms work
4. Update error handling

### Adding New UI Components

1. Create view in `Sources/UI/`
2. Follow SwiftUI best practices
3. Add accessibility support
4. Test on different screen sizes

## Reporting Issues

When reporting issues, please include:

1. **Description**: Clear description of the problem
2. **Steps to Reproduce**: Step-by-step instructions
3. **Expected Behavior**: What you expected to happen
4. **Actual Behavior**: What actually happened
5. **Environment**: macOS version, Xcode version
6. **Screenshots**: If applicable
7. **Logs**: Console output if relevant

## Feature Requests

When requesting features, please:

1. Describe the feature clearly
2. Explain why it would be useful
3. Provide examples if possible
4. Consider implementation complexity
5. Check if similar features exist

## Code of Conduct

- Be respectful and inclusive
- Help others learn and grow
- Provide constructive feedback
- Follow the project's coding standards
- Respect the maintainers' time

## Getting Help

- Check existing issues and pull requests
- Ask questions in issues or discussions
- Review the documentation
- Join community discussions

## License

By contributing to Tray Lang, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing to Tray Lang! 🚀 
