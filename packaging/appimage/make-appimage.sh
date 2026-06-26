#!/usr/bin/env bash
set -euo pipefail

# Simple AppImage builder script. Requires linuxdeploy and appimagetool installed.
# Adjust APPDIR contents and binary path as needed.

APPNAME=DeepCool-Desktop
VERSION=0.1.0
BUILD_DIR="$(pwd)/appdir"
BIN_SRC="../flutter_desktop/build/linux/x64/release/bundle/deepcool_desktop_app"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/usr/bin"
cp "$BIN_SRC" "$BUILD_DIR/usr/bin/deepcool-desktop"

# copy necessary libraries/data
mkdir -p "$BUILD_DIR/usr/share/applications"
cat > "$BUILD_DIR/usr/share/applications/deepcool-desktop.desktop" <<EOF
[Desktop Entry]
Name=DeepCool Desktop
Exec=deepcool-desktop
Type=Application
Categories=Utility;
EOF

echo "Run linuxdeploy (with plugins) to gather runtime deps..."
linuxdeploy --appdir "$BUILD_DIR" --output appimage

echo "AppImage created."
