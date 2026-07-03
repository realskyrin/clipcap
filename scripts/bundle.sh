#!/bin/bash
set -e

# Build configuration
# - CONFIG=debug|release  (default: debug)
# - UNIVERSAL=1           build a fat arm64+x86_64 binary (default: host arch only)
CONFIG="${CONFIG:-debug}"
UNIVERSAL="${UNIVERSAL:-0}"

for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --release)   CONFIG="release" ;;
        --debug)     CONFIG="debug" ;;
    esac
done

# Paths
PRODUCT_NAME="clipcap"
APP_NAME="$PRODUCT_NAME.app"
APP_DIR="build/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
PLUGINS="$CONTENTS/PlugIns"
EXTENSION_PRODUCT_NAME="ClipcapShareExtension"
EXTENSION_NAME="$EXTENSION_PRODUCT_NAME.appex"
EXTENSION_DIR="$PLUGINS/$EXTENSION_NAME"
EXTENSION_CONTENTS="$EXTENSION_DIR/Contents"
EXTENSION_MACOS="$EXTENSION_CONTENTS/MacOS"
EXTENSION_RESOURCES="$EXTENSION_CONTENTS/Resources"

# Build binary
if [ "$UNIVERSAL" = "1" ]; then
    echo "Building $PRODUCT_NAME ($CONFIG, universal: arm64 + x86_64)..."
    swift build -c "$CONFIG" --arch arm64 --arch x86_64
    # SwiftPM emits the merged universal binary under .build/apple/Products/<Config>/
    CONFIG_CAP="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
    BUILD_BIN=".build/apple/Products/$CONFIG_CAP/$PRODUCT_NAME"
    EXTENSION_BUILD_BIN=".build/apple/Products/$CONFIG_CAP/$EXTENSION_PRODUCT_NAME"
    if [ ! -f "$BUILD_BIN" ] || [ ! -f "$EXTENSION_BUILD_BIN" ]; then
        # Fallback: merge per-arch binaries with lipo
        ARM_BIN=".build/arm64-apple-macosx/$CONFIG/$PRODUCT_NAME"
        X86_BIN=".build/x86_64-apple-macosx/$CONFIG/$PRODUCT_NAME"
        EXTENSION_ARM_BIN=".build/arm64-apple-macosx/$CONFIG/$EXTENSION_PRODUCT_NAME"
        EXTENSION_X86_BIN=".build/x86_64-apple-macosx/$CONFIG/$EXTENSION_PRODUCT_NAME"
        if [ -f "$ARM_BIN" ] && [ -f "$X86_BIN" ]; then
            BUILD_BIN=".build/$CONFIG/$PRODUCT_NAME-universal"
            lipo -create -output "$BUILD_BIN" "$ARM_BIN" "$X86_BIN"
        else
            echo "error: universal binary not found at $BUILD_BIN and per-arch fallbacks missing" >&2
            exit 1
        fi
        if [ -f "$EXTENSION_ARM_BIN" ] && [ -f "$EXTENSION_X86_BIN" ]; then
            EXTENSION_BUILD_BIN=".build/$CONFIG/$EXTENSION_PRODUCT_NAME-universal"
            lipo -create -output "$EXTENSION_BUILD_BIN" "$EXTENSION_ARM_BIN" "$EXTENSION_X86_BIN"
        else
            echo "error: universal extension binary not found at $EXTENSION_BUILD_BIN and per-arch fallbacks missing" >&2
            exit 1
        fi
    fi
else
    echo "Building $PRODUCT_NAME ($CONFIG, host arch only)..."
    swift build -c "$CONFIG"
    BUILD_BIN=".build/$CONFIG/$PRODUCT_NAME"
    EXTENSION_BUILD_BIN=".build/$CONFIG/$EXTENSION_PRODUCT_NAME"
fi

if [ ! -f "$BUILD_BIN" ]; then
    echo "error: app binary not found at $BUILD_BIN" >&2
    exit 1
fi

if [ ! -f "$EXTENSION_BUILD_BIN" ]; then
    echo "error: share extension binary not found at $EXTENSION_BUILD_BIN" >&2
    exit 1
fi

# Clean previous bundle
rm -rf "$APP_DIR"

# Create .app bundle structure
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$EXTENSION_MACOS"
mkdir -p "$EXTENSION_RESOURCES"

# Copy binary
cp "$BUILD_BIN" "$MACOS/$PRODUCT_NAME"

# Copy share extension bundle
cp "$EXTENSION_BUILD_BIN" "$EXTENSION_MACOS/$EXTENSION_PRODUCT_NAME"
cp "clipcap-share-extension/Info.plist" "$EXTENSION_CONTENTS/Info.plist"
cp "Resources/AppIcon.icns" "$EXTENSION_RESOURCES/AppIcon.icns"

# Copy Info.plist
cp "clipcap/App/Info.plist" "$CONTENTS/Info.plist"

# Copy app icon
cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"

# Copy menu bar icon source. The SVG lives in design/ so tweaking it updates the
# app bundle on the next rebuild without touching Swift code.
cp "design/menuBarIcon.svg" "$RESOURCES/MenuBarIcon.svg"

# Copy localization bundles (.lproj). The app loads these directly for its
# in-app language picker — see Localizer.swift.
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$RESOURCES/"
done

# Code signing
# -----------------------------------------------------------------------------
# Sign with clipcap's independent identity. This app intentionally does not
# request screen or input-monitoring privacy grants, so it must not reuse the
# original app's signing identity.
#
# Import the cert once if you create one:
#   security import ~/Desktop/clipcap-signing.p12 \
#     -k ~/Library/Keychains/login.keychain-db -P clipcap -T /usr/bin/codesign
#
# Override the identity with the SIGN_IDENTITY env var. If the cert isn't in the
# keychain, fall back to ad-hoc signing.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIGN_IDENTITY="${SIGN_IDENTITY:-clipcap Self-Signed}"
sign_bundles() {
    local identity="$1"
    codesign --force --entitlements "$SCRIPT_DIR/clipcap-share-extension.entitlements" \
        --sign "$identity" "$EXTENSION_DIR"
    codesign --force --entitlements "$SCRIPT_DIR/clipcap.entitlements" \
        --sign "$identity" "$APP_DIR"
}

if security find-identity -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
    echo "Signing with: $SIGN_IDENTITY"
    sign_bundles "$SIGN_IDENTITY"
else
    echo "warning: '$SIGN_IDENTITY' not found in keychain — falling back to ad-hoc signing." >&2
    sign_bundles -
fi

echo "✅ Built and signed $APP_DIR"
ARCHS=$(lipo -archs "$MACOS/$PRODUCT_NAME" 2>/dev/null || echo "unknown")
echo "   Architectures: $ARCHS"
echo ""
echo "To run:"
echo "  open build/$APP_NAME"
echo ""
echo "To install to /Applications:"
echo "  cp -r build/$APP_NAME /Applications/"
