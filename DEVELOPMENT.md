# Folderium Development Guide

## Project Overview

Folderium is a native macOS file manager built entirely in Swift using SwiftUI. It provides a dual-pane interface with advanced features like archive support, global search, and terminal integration.

## Architecture

### Core Components

1. **FolderiumApp.swift** - Main app entry point and window management
2. **ContentView.swift** - Root view with tab management
3. **DualPaneView.swift** - Dual-pane file browser interface
4. **Managers/** - Core functionality modules
    - **FileManager.swift** - File system operations
    - **ArchiveManager.swift** - Archive handling (ZIP, RAR, 7Z, etc.)
    - **SearchManager.swift** - Search functionality (local and Spotlight)
    - **TerminalManager.swift** - Terminal integration

### Key Features Implemented

✅ **Dual-Pane Layout**

-   Side-by-side file browsing
-   Independent navigation
-   Drag and drop support

✅ **Archive Support**

-   ZIP creation and extraction
-   TAR, GZIP, BZIP2 support
-   Placeholder for RAR, 7Z, ISO, CAB, LZH
-   Native macOS integration

✅ **Tab Management**

-   Multiple tabs per window
-   Tab switching and closing
-   Independent file operations

✅ **Search Capabilities**

-   Instant file filtering
-   Regex support
-   Spotlight integration
-   Content search

✅ **Terminal Integration**

-   Terminal.app and iTerm2 support
-   Directory synchronization
-   Built-in terminal view

✅ **Privacy-First Design**

-   No data collection
-   Local operations only
-   No telemetry

## Development Setup

### Prerequisites

-   macOS 14.0 or later
-   Xcode 15.0 or later
-   Swift 5.9 or later

### Building the Project

1. **Clone the repository:**

    ```bash
    git clone https://github.com/yourusername/folderium.git
    cd folderium
    ```

2. **Open in Xcode:**

    ```bash
    open Folderium.xcodeproj
    ```

3. **Build and run:**
    - Press ⌘+R in Xcode
    - Or use: `xcodebuild -project Folderium.xcodeproj -scheme Folderium -configuration Debug build`

### Verification

Run the verification script to check project integrity:

```bash
./scripts/verify_build.sh
```

### Creating DMG

Build a distributable DMG file:

```bash
./scripts/build_dmg.sh
```

## Code Style Guidelines

### Swift Conventions

-   Follow Swift API Design Guidelines
-   Use descriptive variable and function names
-   Prefer `let` over `var` when possible
-   Use guard statements for early returns

### SwiftUI Best Practices

-   Use `@StateObject` for owned objects
-   Use `@ObservedObject` for passed objects
-   Prefer `@State` for simple local state
-   Use `@Published` for reactive properties

### File Organization

-   Group related functionality in managers
-   Keep views focused and composable
-   Use extensions for protocol conformance
-   Document public APIs

## Testing Strategy

### Unit Tests

-   Test individual manager classes
-   Mock external dependencies
-   Test error conditions

### Integration Tests

-   Test file operations
-   Test archive handling
-   Test search functionality

### UI Tests

-   Test user interactions
-   Test navigation flows
-   Test accessibility

## Performance Considerations

### File Operations

-   Use background queues for heavy operations
-   Implement proper error handling
-   Cache frequently accessed data

### Memory Management

-   Use weak references where appropriate
-   Implement proper cleanup
-   Monitor memory usage

### UI Responsiveness

-   Use async/await for long operations
-   Update UI on main thread
-   Show progress indicators

## Security Considerations

### Sandboxing

-   App runs in sandboxed environment
-   Request only necessary entitlements
-   Validate all file operations

### File Access

-   Use security-scoped bookmarks
-   Respect user privacy
-   No data collection

## Deployment

### Code Signing

-   Use Developer ID for distribution
-   Sign all binaries
-   Notarize the app

### DMG Creation

-   Include proper app bundle
-   Add Applications symlink
-   Use appropriate compression

### App Store (Future)

-   Follow App Store guidelines
-   Implement proper entitlements
-   Add privacy policy

## Contributing

### Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Code Review

-   All code must be reviewed
-   Tests must pass
-   Documentation must be updated

## Troubleshooting

### Common Issues

**Build Errors:**

-   Ensure Xcode is properly installed
-   Check deployment target
-   Verify all dependencies

**Runtime Errors:**

-   Check entitlements
-   Verify file permissions
-   Check console logs

**Archive Issues:**

-   Ensure system tools are available
-   Check file permissions
-   Verify archive format support

### Debugging

**Enable Debug Logging:**

```swift
#if DEBUG
print("Debug: \(message)")
#endif
```

**Use Xcode Debugger:**

-   Set breakpoints
-   Use LLDB commands
-   Profile memory usage

## Future Enhancements

### Planned Features

-   [ ] Plugin system for custom formats
-   [ ] File preview pane
-   [ ] Batch operations
-   [ ] Custom themes
-   [ ] File synchronization
-   [ ] Network drive support

### Technical Improvements

-   [ ] Better error handling
-   [ ] Performance optimizations
-   [ ] Accessibility improvements
-   [ ] Localization support

## Resources

### Documentation

-   [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
-   [AppKit Documentation](https://developer.apple.com/documentation/appkit)
-   [File System Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/)

### Tools

-   [SwiftLint](https://github.com/realm/SwiftLint) - Code style enforcement
-   [Instruments](https://developer.apple.com/instruments/) - Performance profiling
-   [Accessibility Inspector](https://developer.apple.com/accessibility/inspector/) - Accessibility testing

### Community

-   [Swift Forums](https://forums.swift.org/)
-   [macOS Developer Community](https://developer.apple.com/forums/)
-   [GitHub Issues](https://github.com/yourusername/folderium/issues)
