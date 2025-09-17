# Contributing to Folderium

Thank you for your interest in contributing to Folderium! This document provides guidelines and information for contributors.

## Code of Conduct

This project follows a code of conduct that we expect all contributors to follow. Please be respectful and constructive in all interactions.

## How to Contribute

### Reporting Issues

Before creating an issue, please:
1. Check if the issue already exists
2. Search through closed issues
3. Make sure you're using the latest version

When creating an issue, please include:
- **macOS version** you're running
- **Steps to reproduce** the issue
- **Expected behavior** vs actual behavior
- **Screenshots** if applicable
- **Console logs** if there are any errors

### Suggesting Features

We welcome feature suggestions! Please:
1. Check if the feature has already been requested
2. Provide a clear description of the feature
3. Explain why it would be useful
4. Consider the impact on the existing codebase

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/your-feature-name`
3. **Make your changes** following our coding standards
4. **Test your changes** thoroughly
5. **Update documentation** if needed
6. **Commit your changes**: `git commit -m 'Add your feature'`
7. **Push to your fork**: `git push origin feature/your-feature-name`
8. **Create a Pull Request**

## Development Setup

### Prerequisites
- macOS 14.0 or later
- Xcode 15.0 or later
- Git

### Getting Started
1. Fork and clone the repository
2. Open `Folderium.xcodeproj` in Xcode
3. Build and run the project
4. Make your changes
5. Test thoroughly

## Coding Standards

### Swift Style Guide
- Follow Apple's Swift API Design Guidelines
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions focused and small

### SwiftUI Best Practices
- Use `@State`, `@Binding`, `@ObservedObject` appropriately
- Prefer `@ViewBuilder` for complex view composition
- Use proper view modifiers and avoid deep nesting
- Follow SwiftUI naming conventions

### Code Organization
- Keep related code together
- Use MARK comments to organize sections
- Follow the existing file structure
- Add proper documentation

## Testing

### Manual Testing
- Test on different macOS versions
- Test with various file types and sizes
- Test edge cases and error conditions
- Test accessibility features

### Areas to Test
- File operations (copy, move, delete, rename)
- Search functionality
- Terminal integration
- Archive operations
- Context menus
- Drag and drop
- Keyboard shortcuts

## Documentation

### Code Documentation
- Add comments for complex functions
- Document public APIs
- Update README.md for new features
- Keep inline documentation current

### User Documentation
- Update feature descriptions
- Add screenshots for new UI elements
- Update keyboard shortcuts
- Document any breaking changes

## Release Process

### Version Numbering
We follow semantic versioning (MAJOR.MINOR.PATCH):
- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Release Checklist
- [ ] All tests pass
- [ ] Documentation updated
- [ ] Version number updated
- [ ] CHANGELOG.md updated
- [ ] Release notes prepared

## Areas for Contribution

### High Priority
- Bug fixes
- Performance improvements
- Accessibility enhancements
- Documentation improvements

### Medium Priority
- New file operations
- UI/UX improvements
- Terminal enhancements
- Search improvements

### Low Priority
- New themes
- Plugin system
- Advanced features

## Getting Help

If you need help:
1. Check the existing issues and discussions
2. Ask questions in the discussions section
3. Join our community chat (if available)
4. Create an issue with the "question" label

## Recognition

Contributors will be recognized in:
- CONTRIBUTORS.md file
- Release notes
- Project documentation

Thank you for contributing to Folderium! 🎉
