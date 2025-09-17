#!/bin/bash

# Folderium DMG Build Script
# This script builds the app and creates a distributable DMG file

set -e

# Configuration
APP_NAME="Folderium"
APP_BUNDLE_ID="com.folderium.app"
VERSION="1.0.0"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_TEMP_DIR="dmg_temp"
DMG_BACKGROUND_IMG="dmg_background.png"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Building Folderium DMG...${NC}"

# Clean previous builds
echo -e "${YELLOW}🧹 Cleaning previous builds...${NC}"
rm -rf "$BUILD_DIR"
rm -rf "$DMG_TEMP_DIR"
rm -f "$DMG_NAME"

# Create build directory
mkdir -p "$BUILD_DIR"
mkdir -p "$DMG_TEMP_DIR"

# Build the app
echo -e "${YELLOW}🔨 Building Xcode project...${NC}"
xcodebuild -project Folderium.xcodeproj \
    -scheme Folderium \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -archivePath "$BUILD_DIR/Folderium.xcarchive" \
    archive

# Copy app to temp directory
echo -e "${YELLOW}📦 Preparing app bundle...${NC}"
cp -R "$BUILD_DIR/Folderium.xcarchive/Products/Applications/Folderium.app" "$DMG_TEMP_DIR/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# Create DMG
echo -e "${YELLOW}💿 Creating DMG...${NC}"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP_DIR" \
    -ov -format UDZO \
    "$DMG_NAME"

# Clean up
echo -e "${YELLOW}🧹 Cleaning up...${NC}"
rm -rf "$DMG_TEMP_DIR"

# Sign the DMG (optional, requires Developer ID)
if command -v codesign &> /dev/null; then
    echo -e "${YELLOW}🔐 Signing DMG...${NC}"
    codesign --force --sign "Developer ID Application: Your Name" "$DMG_NAME" || echo -e "${RED}⚠️  DMG signing failed (this is optional)${NC}"
fi

# Verify the DMG
echo -e "${YELLOW}✅ Verifying DMG...${NC}"
hdiutil verify "$DMG_NAME"

echo -e "${GREEN}🎉 DMG created successfully: $DMG_NAME${NC}"
echo -e "${GREEN}📊 DMG size: $(du -h "$DMG_NAME" | cut -f1)${NC}"

# Open the DMG in Finder
open -R "$DMG_NAME"
