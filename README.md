# Folderium

A native macOS file manager with dual-pane layout, inspired by Marta (but open-source). Built entirely in Swift and SwiftUI.

![Folderium Screenshot](https://folderium.com/screenshot.png)

## Features

### 🗂️ Dual-Pane Interface

-   **Two-pane layout** for efficient file management
-   **Resizable panes** with customizable proportions
-   **Active pane highlighting** with visual focus indicators
-   **Unlimited windows** support

### 🔍 Advanced Search

-   **Real-time filtering** as you type
-   **Per-pane search** - each pane has its own search field
-   **System-wide search** integration with macOS Spotlight
-   **Regex support** for advanced search patterns

### 📁 File Operations

-   **Copy, Cut, Paste** with conflict resolution
-   **Drag & Drop** between panes
-   **Rename** with native macOS dialogs
-   **Delete** and **Move to Trash** with confirmation
-   **New File/Folder** creation with custom naming
-   **Context menus** for all file types

### 🗜️ Archive Support

-   **Compress** multiple files into archives
-   **Extract** from various archive formats
-   **Supported formats**: ZIP, RAR, 7Z, XAR, TAR, GZIP, BZIP2, XZ, LZ, LZMA, Z, CAB, ISO, LZH

### 💻 Terminal Integration

-   **Embedded terminal** below each pane
-   **Two-way directory sync** - terminal follows pane navigation
-   **Full terminal functionality** with command history
-   **External terminal** support

### 🎨 Modern UI

-   **Native macOS design** following Apple's Human Interface Guidelines
-   **File type icons** with color coding
-   **Alternating row colors** for better readability
-   **Status bar** showing file/folder counts and total size
-   **Breadcrumb navigation** for easy path tracking

### ☁️ Cloud Storage Support

-   **OneDrive, Dropbox, Google Drive, iCloud** integration
-   **Symbolic link resolution** for cloud folders
-   **Special handling** for cloud storage directories

## Installation

### Requirements

-   macOS 14.0 or later
-   Xcode 15.0 or later (for building from source)

### Building from Source

1. **Clone the repository**

    ```bash
    git clone https://github.com/yourusername/folderium.git
    cd folderium
    ```

2. **Open in Xcode**

    ```bash
    open Folderium.xcodeproj
    ```

3. **Build and Run**
    - Select your target device/simulator
    - Press `Cmd + R` to build and run

### Creating a DMG

1. **Archive the app**

    - In Xcode: Product → Archive
    - Select the archive and click "Distribute App"
    - Choose "Copy App" and save to a folder

2. **Create DMG** (using create-dmg tool)
    ```bash
    brew install create-dmg
    create-dmg --volname "Folderium" --window-pos 200 120 --window-size 600 300 --icon-size 100 --icon "Folderium.app" 175 120 --hide-extension "Folderium.app" --app-drop-link 425 120 "Folderium.dmg" "Folderium.app"
    ```

## Usage

### Basic Navigation

-   **Double-click folders** to navigate into them
-   **Double-click files** to open with default application
-   **Right-click** for context menus
-   **Use breadcrumbs** to navigate back to parent directories

### File Selection

-   **Single click** to select a file
-   **Command + Click** to toggle selection
-   **Shift + Click** to select a range
-   **Drag** to select multiple files

### Search

-   **Type in search field** to filter files in real-time
-   **Each pane** has its own independent search
-   **Clear search** to show all files

### Terminal

-   **Click terminal button** to show/hide embedded terminal
-   **Terminal automatically syncs** with current pane directory
-   **Use full terminal commands** for advanced operations

## Keyboard Shortcuts

| Shortcut       | Action                  |
| -------------- | ----------------------- |
| `Cmd + N`      | New Window              |
| `Cmd + W`      | Close Window            |
| `Cmd + Q`      | Quit Application        |
| `Space`        | Compress Selected Files |
| `Cmd + C`      | Copy Selected           |
| `Cmd + X`      | Cut Selected            |
| `Cmd + V`      | Paste                   |
| `Delete`       | Move to Trash           |
| `Cmd + Delete` | Delete Permanently      |

## File Type Support

### Icons & Colors

-   **Images**: Green folder icon (JPG, PNG, GIF, SVG, etc.)
-   **Documents**: Blue/Red icons (PDF, DOC, TXT, etc.)
-   **Code Files**: Purple icons (Swift, Python, JavaScript, etc.)
-   **Archives**: Brown archive icon (ZIP, RAR, 7Z, etc.)
-   **Media**: Pink/Purple icons (MP3, MP4, etc.)
-   **Folders**: Blue folder icons
-   **Symbolic Links**: Blue folder with plus badge

## Architecture

### Core Components

-   **DualPaneView**: Main dual-pane interface
-   **FilePaneView**: Individual pane implementation
-   **FileItem**: File representation model
-   **ArchiveManager**: Archive compression/extraction
-   **SearchManager**: File search functionality
-   **FileManager**: File system operations

### Technologies Used

-   **SwiftUI**: Modern declarative UI framework
-   **AppKit**: Native macOS integration
-   **CoreSpotlight**: System-wide search integration
-   **Process**: Terminal integration
-   **FileManager**: File system operations

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Commit your changes: `git commit -m 'Add amazing feature'`
5. Push to the branch: `git push origin feature/amazing-feature`
6. Open a Pull Request

## Roadmap

-   [ ] **Tabs support** for multiple directories per pane
-   [ ] **Bookmarks** for frequently accessed folders
-   [ ] **Split view** for file comparison
-   [ ] **Batch operations** for multiple files
-   [ ] **Custom themes** and appearance options
-   [ ] **Plugin system** for extensions
-   [ ] **FTP/SFTP** support
-   [ ] **File preview** pane

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

-   Inspired by [Marta](https://marta.sh/) file manager
-   Built with SwiftUI and native macOS technologies
-   Icons from SF Symbols
-   App icon from (https://www.svgrepo.com/svg/514322/folder)

## Support

If you encounter any issues or have questions:

1. **Check the Issues** tab for existing problems
2. **Create a new issue** with detailed information
3. **Join our discussions** for community support

---

**Folderium** - A modern file manager for macOS, built with ❤️ using Swift and SwiftUI.
