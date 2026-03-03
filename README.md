# Folderium

Folderium is an open-source, native macOS file manager built with Swift and SwiftUI.
It focuses on fast local file operations with a dual-pane workflow and zero telemetry.

## Highlights

- Dual-pane file browsing with independent navigation per pane
- Explorer-style familiarity mode (toggle in app settings)
- Quick Access sidebar with favorites, recent folders, and mounted drives
- Explorer-like navigation controls per pane (Back, Forward, Up, path bar)
- Multi-window support (`Cmd + N` creates a new window)
- File operations: copy, move, delete, move to Trash, create file/folder, rename
- File conflict dialogs for copy/move/drop (`Replace`, `Keep Both`, `Skip`)
- Keyboard convenience: `F2` rename for selected item
- Search features: local filename search, regex search, file-content search, Spotlight search
  - Includes token filters in pane search such as `ext:`, `type:`, `size>`, `size<`
- Archive support with system tools:
  - Create: ZIP, TAR, GZIP, BZIP2
  - Extract/List: ZIP, TAR, GZIP, BZIP2
  - 7Z/RAR/ISO/CAB/LZH currently return unsupported
- Terminal integration:
  - Built-in terminal window and command execution
  - Directory synchronization support
- Privacy-first by design: local operations only, no analytics in the app

## Requirements

- macOS 14.0+
- Xcode 15+ (for local development)

## Quick Start

```bash
git clone https://github.com/yourusername/folderium.git
cd folderium
open Folderium.xcodeproj
```

Then run in Xcode with `Cmd + R`.

## Build From CLI

```bash
xcodebuild -project Folderium.xcodeproj -scheme Folderium -configuration Debug build
```

## Project Scripts

- Verify project/build health:

  ```bash
  ./scripts/verify_build.sh
  ```

- Build distributable DMG:

  ```bash
  ./scripts/build_dmg.sh
  ```

## Project Structure

```text
folderium/
├── Folderium/
│   ├── FolderiumApp.swift
│   ├── ContentView.swift
│   ├── DualPaneView.swift
│   └── Managers/
│       ├── FileManager.swift
│       ├── ArchiveManager.swift
│       ├── SearchManager.swift
│       └── TerminalManager.swift
├── scripts/
├── .github/workflows/build.yml
├── README.md
└── CONTRIBUTING.md
```

## Architecture Overview

- `FolderiumApp.swift`: app entry, window behavior, command menu integration
- `ContentView.swift`: top-level layout (dual-pane area + preview pane)
- `DualPaneView.swift`: core file browser UI/state and pane interactions
- `Managers/FileManager.swift`: local filesystem operations
- `Managers/ArchiveManager.swift`: archive create/extract/list using macOS CLI tools
- `Managers/SearchManager.swift`: local, content, and Spotlight search
- `Managers/TerminalManager.swift`: built-in terminal workflows

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR.

## License

MIT — see [LICENSE](LICENSE).
