```bash
#!/usr/bin/env bash
set -euo pipefail

APPNAME="Deepcool-Digital-Linux"
VERSION="${1:-${VERSION:-0.1.0}}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BUILD_DIR="$SCRIPT_DIR/appdir"
BUNDLE_SRC="$REPO_ROOT/flutter_desktop/build/linux/x64/release/bundle"

rm -rf "$BUILD_DIR"

mkdir -p "$BUILD_DIR/usr/bin"
mkdir -p "$BUILD_DIR/usr/lib"
mkdir -p "$BUILD_DIR/usr/share/deepcool_desktop_app"
mkdir -p "$BUILD_DIR/usr/share/applications"
mkdir -p "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps"

if [ ! -f "$BUNDLE_SRC/deepcool_desktop_app" ]; then
  echo "ERROR: Flutter Linux binary not found:"
  echo "$BUNDLE_SRC/deepcool_desktop_app"
  echo
  echo "Run this first:"
  echo "cd flutter_desktop && flutter build linux --release"
  exit 1
fi

echo "Copying Flutter binary..."
cp "$BUNDLE_SRC/deepcool_desktop_app" "$BUILD_DIR/usr/bin/deepcool-desktop"
chmod +x "$BUILD_DIR/usr/bin/deepcool-desktop"

echo "Copying Flutter runtime libraries..."
if [ -d "$BUNDLE_SRC/lib" ]; then
  cp -r "$BUNDLE_SRC/lib/"* "$BUILD_DIR/usr/lib/" || true
fi

echo "Copying Flutter data..."
if [ -d "$BUNDLE_SRC/data" ]; then
  cp -r "$BUNDLE_SRC/data/"* "$BUILD_DIR/usr/share/deepcool_desktop_app/" || true
fi

echo "Creating desktop file..."
cat > "$BUILD_DIR/usr/share/applications/com.rgs.deepcool_linux.desktop" <<EOF
[Desktop Entry]
Name=Deepcool Digital Linux
Exec=deepcool-desktop
Type=Application
Categories=Utility;
Icon=com.rgs.deepcool_linux
StartupWMClass=deepcool-desktop
EOF

echo "Copying app icon..."
if [ -f "$REPO_ROOT/flutter_desktop/assets/app-icon.png" ]; then
  cp "$REPO_ROOT/flutter_desktop/assets/app-icon.png" \
    "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps/com.rgs.deepcool_linux.png"
else
  echo "WARNING: app-icon.png not found at:"
  echo "$REPO_ROOT/flutter_desktop/assets/app-icon.png"
fi

echo "Building AppImage..."
export APPNAME
export VERSION
export APPIMAGE_EXTRACT_AND_RUN=1
export LD_LIBRARY_PATH="$BUILD_DIR/usr/lib:${LD_LIBRARY_PATH:-}"

linuxdeploy \
  --appdir "$BUILD_DIR" \
  -e "$BUILD_DIR/usr/bin/deepcool-desktop" \
  -d "$BUILD_DIR/usr/share/applications/com.rgs.deepcool_linux.desktop" \
  -i "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps/com.rgs.deepcool_linux.png" \
  --output appimage

echo "AppImage created."
```
