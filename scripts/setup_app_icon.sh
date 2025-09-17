#!/bin/bash

# Folderium App Icon Setup Script
# This script converts the SVG icon to all required PNG sizes for macOS app icons

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🎨 Setting up Folderium app icon...${NC}"

# Check if SVG file exists
SVG_FILE="folderium.svg"
if [ ! -f "$SVG_FILE" ]; then
    echo -e "${RED}❌ SVG file not found: $SVG_FILE${NC}"
    exit 1
fi

# Check if we have required tools
if ! command -v rsvg-convert &> /dev/null; then
    echo -e "${YELLOW}⚠️  rsvg-convert not found. Installing librsvg...${NC}"
    if command -v brew &> /dev/null; then
        brew install librsvg
    else
        echo -e "${RED}❌ Homebrew not found. Please install librsvg manually:${NC}"
        echo -e "${YELLOW}brew install librsvg${NC}"
        exit 1
    fi
fi

# Define icon sizes for macOS
declare -a sizes=(
    "16:icon_16x16"
    "32:icon_16x16@2x"
    "32:icon_32x32"
    "64:icon_32x32@2x"
    "128:icon_128x128"
    "256:icon_128x128@2x"
    "256:icon_256x256"
    "512:icon_256x256@2x"
    "512:icon_512x512"
    "1024:icon_512x512@2x"
)

# Create AppIcon directory
APPICON_DIR="Folderium/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$APPICON_DIR"

echo -e "${YELLOW}🔄 Converting SVG to PNG icons...${NC}"

# Convert SVG to different sizes
for size_info in "${sizes[@]}"; do
    IFS=':' read -r size filename <<< "$size_info"
    output_file="$APPICON_DIR/${filename}.png"
    
    echo -e "${YELLOW}  📏 Creating ${size}x${size} icon: ${filename}.png${NC}"
    rsvg-convert -w "$size" -h "$size" "$SVG_FILE" -o "$output_file"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✅ Created: ${filename}.png${NC}"
    else
        echo -e "${RED}  ❌ Failed to create: ${filename}.png${NC}"
        exit 1
    fi
done

echo -e "${YELLOW}📝 Updating Contents.json...${NC}"

# Create Contents.json for AppIcon
cat > "$APPICON_DIR/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo -e "${GREEN}✅ App icon setup complete!${NC}"
echo -e "${GREEN}📁 Icon files created in: $APPICON_DIR${NC}"
echo -e "${GREEN}🎯 Your app now has a custom icon based on folderium.svg${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "${YELLOW}1. Open Folderium.xcodeproj in Xcode${NC}"
echo -e "${YELLOW}2. The app icon should now appear in the project navigator${NC}"
echo -e "${YELLOW}3. Build and run to see your custom icon!${NC}"
