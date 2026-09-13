#!/bin/bash
# scripts/install.sh
# Build and install Hearsay.app and the `hearsay` CLI from source.

set -e

cd "$(dirname "$0")/.."

APP_NAME="Hearsay"
APP_DIR="$HOME/Applications"
TARGET_APP="$APP_DIR/$APP_NAME.app"
BIN_LINK="/opt/homebrew/bin/hearsay"
ALT_BIN_LINK="$HOME/.local/bin/hearsay"
QWEN_BACKUP="$HOME/.local/share/hearsay/qwen_asr"

LAUNCH=false
for arg in "$@"; do
    case "$arg" in
        --launch)
            LAUNCH=true
            ;;
        --help|-h)
            echo "Usage: ./scripts/install.sh [--launch]"
            echo "Builds Hearsay from source and installs it into ~/Applications with CLI symlink."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: ./scripts/install.sh [--launch]"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Hearsay Install ===${NC}"

# Check for xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo -e "${YELLOW}Installing xcodegen via Homebrew...${NC}"
    brew install xcodegen
fi

# Stop running Hearsay if active
echo -e "${YELLOW}Stopping any running Hearsay processes...${NC}"
pkill -f "Hearsay.app" 2>/dev/null || true

# Generate Xcode project if missing or stale
if [ ! -d "Hearsay.xcodeproj" ] || [ "project.yml" -nt "Hearsay.xcodeproj" ]; then
    echo -e "${YELLOW}Generating Xcode project...${NC}"
    xcodegen generate
fi

# Verify xcodebuild works
if ! xcodebuild -checkFirstLaunchStatus 2>/dev/null; then
    if ! xcodebuild -version &>/dev/null; then
        echo -e "${RED}Error: xcodebuild is failing to load plugins.${NC}"
        echo -e "${YELLOW}Please run: sudo xcodebuild -runFirstLaunch${NC}"
        exit 1
    fi
fi

# Build Parakeet Helper
echo -e "${YELLOW}Building HearsayParakeetHelper...${NC}"
xcodebuild -project Hearsay.xcodeproj \
    -scheme HearsayParakeetHelper \
    -configuration Release \
    -derivedDataPath build \
    -destination 'platform=macOS,arch=arm64' \
    -skipMacroValidation \
    build ARCHS=arm64 ONLY_ACTIVE_ARCH=NO

# Build CLI
echo -e "${YELLOW}Building HearsayCLI...${NC}"
xcodebuild -project Hearsay.xcodeproj \
    -scheme HearsayCLI \
    -configuration Release \
    -derivedDataPath build \
    -destination 'platform=macOS,arch=arm64' \
    -skipMacroValidation \
    build ARCHS=arm64 ONLY_ACTIVE_ARCH=NO

# Build Main App
echo -e "${YELLOW}Building Hearsay.app...${NC}"
xcodebuild -project Hearsay.xcodeproj \
    -scheme Hearsay \
    -configuration Release \
    -derivedDataPath build \
    -destination 'platform=macOS,arch=arm64' \
    -skipMacroValidation \
    build ARCHS=arm64 ONLY_ACTIVE_ARCH=NO

BUILT_APP="build/Build/Products/Release/$APP_NAME.app"
BUILT_HELPER="build/Build/Products/Release/HearsayParakeetHelper"
BUILT_CLI="build/Build/Products/Release/hearsay"

if [ ! -d "$BUILT_APP" ]; then
    echo -e "${RED}Error: Build output not found at $BUILT_APP${NC}"
    exit 1
fi

# Bundle helper into app
if [ -f "$BUILT_HELPER" ]; then
    mkdir -p "$BUILT_APP/Contents/MacOS"
    cp "$BUILT_HELPER" "$BUILT_APP/Contents/MacOS/HearsayParakeetHelper"
    chmod 755 "$BUILT_APP/Contents/MacOS/HearsayParakeetHelper"
    codesign --force --sign - "$BUILT_APP/Contents/MacOS/HearsayParakeetHelper"
fi

# Bundle CLI into app Resources
if [ -f "$BUILT_CLI" ]; then
    mkdir -p "$BUILT_APP/Contents/Resources"
    cp "$BUILT_CLI" "$BUILT_APP/Contents/Resources/hearsay"
    chmod 755 "$BUILT_APP/Contents/Resources/hearsay"
    codesign --force --sign - "$BUILT_APP/Contents/Resources/hearsay"
fi

# Bundle qwen_asr if available
if [ -f "$QWEN_BACKUP" ]; then
    cp "$QWEN_BACKUP" "$BUILT_APP/Contents/MacOS/qwen_asr"
    chmod 755 "$BUILT_APP/Contents/MacOS/qwen_asr"
    codesign --force --sign - "$BUILT_APP/Contents/MacOS/qwen_asr"
elif [ -f "$HOME/work/misc/qwen-asr/qwen_asr" ]; then
    cp "$HOME/work/misc/qwen-asr/qwen_asr" "$BUILT_APP/Contents/MacOS/qwen_asr"
    chmod 755 "$BUILT_APP/Contents/MacOS/qwen_asr"
    codesign --force --sign - "$BUILT_APP/Contents/MacOS/qwen_asr"
fi

# Sign the overall bundle
echo -e "${YELLOW}Codesigning Hearsay.app...${NC}"
codesign --force --sign - --entitlements Hearsay/Hearsay.entitlements "$BUILT_APP"

# Install into ~/Applications
echo -e "${YELLOW}Installing to $TARGET_APP...${NC}"
mkdir -p "$APP_DIR"
rm -rf "$TARGET_APP"
cp -R "$BUILT_APP" "$TARGET_APP"

# Create symlink for CLI
INSTALLED_CLI="$TARGET_APP/Contents/Resources/hearsay"
if [ -f "$INSTALLED_CLI" ]; then
    echo -e "${YELLOW}Installing CLI symlink...${NC}"
    if [ -w "/opt/homebrew/bin" ]; then
        ln -sf "$INSTALLED_CLI" "$BIN_LINK"
        echo -e "${GREEN}Linked CLI to $BIN_LINK${NC}"
    else
        mkdir -p "$HOME/.local/bin"
        ln -sf "$INSTALLED_CLI" "$ALT_BIN_LINK"
        echo -e "${GREEN}Linked CLI to $ALT_BIN_LINK${NC}"
    fi
fi

echo -e "${GREEN}✓ Successfully installed Hearsay to $TARGET_APP${NC}"

if [ "$LAUNCH" = true ]; then
    echo -e "${GREEN}Launching Hearsay...${NC}"
    open "$TARGET_APP"
fi
