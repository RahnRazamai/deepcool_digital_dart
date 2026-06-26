#!/usr/bin/env bash
set -euo pipefail

# Simple AppImage builder script. Requires linuxdeploy and appimagetool installed.
# Adjust APPDIR contents and binary path as needed.

APPNAME=Deepcool-Digital-Linux
VERSION=0.1.0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/appimage/appdir"
BUNDLE_SRC="$REPO_ROOT/../flutter_desktop/build/linux/x64/release/bundle"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/usr/bin"
mkdir -p "$BUILD_DIR/usr/lib"

# Copy the binary
cp "$BUNDLE_SRC/deepcool_desktop_app" "$BUILD_DIR/usr/bin/deepcool-desktop"

# Copy Flutter runtime libraries and data
if [ -d "$BUNDLE_SRC/lib" ]; then
	cp -r "$BUNDLE_SRC/lib"/* "$BUILD_DIR/usr/lib/" || true
fi
if [ -d "$BUNDLE_SRC/data" ]; then
	cp -r "$BUNDLE_SRC/data" "$BUILD_DIR/usr/share/deepcool_desktop_app/" || true
fi

# copy necessary libraries/data
mkdir -p "$BUILD_DIR/usr/share/applications"
cat > "$BUILD_DIR/usr/share/applications/com.rgs.deepcool_linux.desktop" <<EOF
[Desktop Entry]
Name=Deepcool Digital Linux
Exec=deepcool-desktop
Type=Application
Categories=Utility;
Icon=com.rgs.deepcool_linux
StartupWMClass=deepcool-desktop
EOF

# Include theme icon so desktop environments show the app icon
mkdir -p "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps"
if [ -f "$REPO_ROOT/../flutter_desktop/assets/app-icon.png" ]; then
	cp "$REPO_ROOT/../flutter_desktop/assets/app-icon.png" "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps/com.rgs.deepcool_linux.png"
fi

echo "Run linuxdeploy (with plugins) to gather runtime deps..."
linuxdeploy --appdir "$BUILD_DIR" --output appimage

echo "AppImage created."
