# Contributing to Folderium

Thanks for contributing to Folderium. This guide explains how to propose changes, develop locally, and submit pull requests.

## Before You Start

- Search open and closed issues to avoid duplicates.
- For bugs, include:
  - macOS version
  - steps to reproduce
  - expected vs actual behavior
  - screenshots and/or logs when helpful
- For features, explain the use case and user impact.

## Development Setup

### Prerequisites

- macOS 14.0+
- Xcode 15+
- Git

### Run Locally

```bash
git clone https://github.com/yourusername/folderium.git
cd folderium
open Folderium.xcodeproj
```

Then run with `Cmd + R` in Xcode.

### Optional CLI Build

```bash
xcodebuild -project Folderium.xcodeproj -scheme Folderium -configuration Debug build
```

### Project Verification Script

```bash
./scripts/verify_build.sh
```

## Pull Request Workflow

1. Fork the repository.
2. Create a branch:

   ```bash
   git checkout -b feature/short-description
   ```

3. Make focused, small changes.
4. Verify the app builds and manually test affected features.
5. Update `README.md` if user-facing behavior changed.
6. Commit with a clear message.
7. Push and open a PR against `main`.

## Coding Guidelines

### Swift / SwiftUI

- Follow Swift API Design Guidelines.
- Keep views and functions focused and readable.
- Prefer descriptive naming over abbreviations.
- Add comments only where logic is non-obvious.
- Follow existing project style in nearby code.

### Project Structure

- UI and interaction flow primarily live under `Folderium/`.
- Domain logic lives in `Folderium/Managers/`.
- Keep new code in the closest existing module unless a new module is justified.

## Testing Expectations

This repository currently relies primarily on build checks and manual validation.

Before opening a PR, test the areas you touched. Common areas:

- file operations (copy/move/delete/rename/create)
- archive operations (create/extract/list where applicable)
- search behavior (local/regex/content/Spotlight)
- terminal integration
- drag and drop and context menu actions

If you add automated tests in the future, include them in your PR and mention how to run them.

## CI

GitHub Actions runs macOS builds for push/PR events (`.github/workflows/build.yml`).
Make sure your branch builds locally before opening a PR.

## Documentation

- Keep `README.md` accurate; it is the primary project documentation.
- Document breaking or behavior-changing decisions in your PR description.

## Release Notes

No in-repo changelog file is required right now.
When preparing a release, summarize notable changes in the GitHub release notes.

## Getting Help

- Open an issue for questions, bugs, or proposals.
- Provide enough context to reproduce and discuss efficiently.

Thanks for helping improve Folderium.
