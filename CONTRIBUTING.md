# Contributing to Tray Lang

Thank you for your interest in contributing to Tray Lang! This document provides guidelines and information for contributors.

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

### Architecture

The project follows a simple architecture:

- **Views**: SwiftUI views for UI components
- **Managers**: Core functionality classes (TrayLangManager)
- **Models**: Data structures and enums
- **Extensions**: Swift extensions for additional functionality

### Testing

- Write unit tests for new functionality
- Test UI components when possible
- Ensure accessibility features work correctly

## Making Changes

### Creating a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### Commit Messages

Use clear, descriptive commit messages:

```
feat: add new language support for French
fix: resolve hotkey capture issue
docs: update README with installation instructions
```

### Pull Request Process

1. Ensure your code builds without errors
2. Run tests to ensure nothing is broken
3. Update documentation if needed
4. Create a pull request with a clear description
5. Wait for review and address any feedback

## Reporting Issues

When reporting issues, please include:

1. **Description**: Clear description of the problem
2. **Steps to Reproduce**: Step-by-step instructions
3. **Expected Behavior**: What you expected to happen
4. **Actual Behavior**: What actually happened
5. **Environment**: macOS version, Xcode version
6. **Screenshots**: If applicable

## Feature Requests

When requesting features, please:

1. Describe the feature clearly
2. Explain why it would be useful
3. Provide examples if possible
4. Consider implementation complexity

## Code of Conduct

- Be respectful and inclusive
- Help others learn and grow
- Provide constructive feedback
- Follow the project's coding standards

## Getting Help

- Check existing issues and pull requests
- Ask questions in issues or discussions
- Review the documentation

## License

By contributing to Tray Lang, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing to Tray Lang! 🚀 
