# Tray Lang

A macOS application for automatic keyboard layout switching for selected text. Tray Lang helps you quickly transform text between different keyboard layouts while simultaneously switching the system keyboard layout.

## Features

- **Automatic Layout Switching**: Transform selected text between different keyboard layouts
- **Customizable Hotkeys**: Configure your own hotkey combinations
- **Character Mapping**: Customize character mappings between layouts
- **Tray Icon**: Easy access from the system tray
- **Auto-launch**: Start automatically with your system
- **Accessibility Integration**: Uses macOS accessibility features for text manipulation

## How It Works

1. **Select Text**: Highlight any text in any application
2. **Press Hotkey**: Use your configured hotkey combination
3. **Automatic Transformation**: The text is transformed to the opposite layout
4. **Layout Switch**: The system keyboard layout is also switched

## Installation

### Requirements
- macOS 14.0 or later
- Accessibility permissions (required for text manipulation)

### Setup
1. Download and run the application
2. Grant accessibility permissions when prompted
3. Configure your hotkey in the settings
4. Customize character mappings if needed

## Usage

### Basic Usage
1. Select text in any application
2. Press your configured hotkey (default: Cmd+1)
3. The text will be transformed and the keyboard layout will switch

### Configuration

#### Hotkey Editor
- Access via tray menu → "Hotkey Editor"
- Press "Start capture" and press your desired key combination
- Press "Confirm" to save

#### Symbols Editor
- Access via tray menu → "Symbols Editor"
- Add custom character mappings
- Use ready-made blocks for common languages
- Edit or delete existing mappings

#### Auto-launch
- Toggle "Auto Launch" in the tray menu
- The app will start automatically with your system

### Supported Languages

The app includes ready-made character mappings for:
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
- Cyrillic ↔ Latin (generic)

## Permissions

Tray Lang requires accessibility permissions to:
- Read selected text from applications
- Replace selected text with transformed content
- Switch keyboard layouts

To grant permissions:
1. Go to System Preferences → Security & Privacy → Accessibility
2. Add Tray Lang to the list of allowed applications
3. Check the box next to Tray Lang

## Development

### Building from Source
1. Clone the repository
2. Open `tray-lang.xcodeproj` in Xcode
3. Build and run the project

### Architecture
- **SwiftUI**: User interface
- **AppKit**: macOS-specific functionality
- **Carbon Framework**: Keyboard layout management
- **Accessibility API**: Text manipulation

### Key Components
- `TrayLangManager`: Main application logic
- `ContentView`: Main application window
- `TrayMenuView`: Tray menu interface
- `HotKeyEditorView`: Hotkey configuration
- `SymbolsEditorView`: Character mapping editor
- `AboutView`: Application information

## Troubleshooting

### Common Issues

**Hotkey not working:**
- Check if accessibility permissions are granted
- Verify the hotkey is not conflicting with other applications
- Try a different key combination

**Text not transforming:**
- Ensure text is selected before pressing the hotkey
- Check character mappings in the Symbols Editor
- Verify the application has accessibility permissions

**App not starting with system:**
- Check the "Auto Launch" toggle in the tray menu
- Verify the app is in the Applications folder

### Debug Information
The app includes debug logging. Check the Console app for detailed information about:
- Hotkey captures
- Text transformations
- Permission status
- Layout switching

## License

© 2024 All rights reserved

## Developer

Developed by s00d
