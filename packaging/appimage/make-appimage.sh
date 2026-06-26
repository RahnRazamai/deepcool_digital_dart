#!/usr/bin/env bash
set -euo pipefail

# Simple AppImage builder script. Requires linuxdeploy and appimagetool installed.
# Adjust APPDIR contents and binary path as needed.

APPNAME=Deepcool-Digital-Linux
VERSION=0.1.0
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/appimage/appdir"
BIN_SRC="$REPO_ROOT/../flutter_desktop/build/linux/x64/release/bundle/deepcool_desktop_app"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/usr/bin"
cp "$BIN_SRC" "$BUILD_DIR/usr/bin/deepcool-desktop"

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
