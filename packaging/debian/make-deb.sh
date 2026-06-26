#!/usr/bin/env bash
set -euo pipefail

# Build a .deb package for Deepcool Digital Linux from the release bundle.
# Usage: ./make-deb.sh [version]

PKGNAME=deepcool-desktop
ARCH=amd64
VERSION=${1:-0.1.0}
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
BUNDLE="$PROJECT_ROOT/flutter_desktop/build/linux/x64/release/bundle/deepcool_desktop_app"
DAEMON_BINARY="$PROJECT_ROOT/build/deepcool-digital-dart"
OUTDIR="$REPO_ROOT/out"
PKGDIR="$OUTDIR/${PKGNAME}_${VERSION}_${ARCH}"
source "$REPO_ROOT/icon-utils.sh"

rm -rf "$PKGDIR"
mkdir -p "$PKGDIR/DEBIAN"
mkdir -p "$PKGDIR/usr/bin"
mkdir -p "$PKGDIR/usr/share/applications"
mkdir -p "$PKGDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$PKGDIR/etc/udev/rules.d"
mkdir -p "$PKGDIR/usr/share/doc/$PKGNAME"

if [ ! -f "$BUNDLE" ]; then
  echo "Release binary not found at $BUNDLE"
  echo "Build with: (from repo root) flutter_desktop && flutter build linux --release"
  exit 1
fi
if [ ! -x "$DAEMON_BINARY" ]; then
  if command -v dart >/dev/null 2>&1; then
    echo "Compiling CLI daemon..."
    (cd "$PROJECT_ROOT" && dart compile exe bin/deepcool_digital_dart.dart -o "$DAEMON_BINARY")
  else
    echo "CLI daemon binary not found at $DAEMON_BINARY"
    echo "Build with: dart compile exe bin/deepcool_digital_dart.dart -o build/deepcool-digital-dart"
    exit 1
  fi
fi

echo "Copying binaries..."
cp "$BUNDLE" "$PKGDIR/usr/bin/deepcool-desktop"
chmod 755 "$PKGDIR/usr/bin/deepcool-desktop"
cp "$DAEMON_BINARY" "$PKGDIR/usr/bin/deepcool-digital-dart"
chmod 755 "$PKGDIR/usr/bin/deepcool-digital-dart"

echo "Installing desktop file and icon..."
if [ -f "$REPO_ROOT/desktop/com.rgs.deepcool_linux.desktop" ]; then
  cp "$REPO_ROOT/desktop/com.rgs.deepcool_linux.desktop" "$PKGDIR/usr/share/applications/"
fi
install_256_icon "$PROJECT_ROOT" "$PKGDIR/usr/share/icons/hicolor/256x256/apps/com.rgs.deepcool_linux.png"

echo "Including udev rule..."
if [ -f "$REPO_ROOT/udev/99-deepcool-digital.rules" ]; then
  cp "$REPO_ROOT/udev/99-deepcool-digital.rules" "$PKGDIR/etc/udev/rules.d/99-deepcool-digital.rules"
fi

cat > "$PKGDIR/DEBIAN/control" <<EOF
Package: $PKGNAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: Your Name <you@example.com>
Depends: libc6 (>= 2.17), libhidapi-hidraw0 | libhidapi-libusb0
Description: DeepCool Desktop GUI for CH170 devices
 A GTK desktop application to control and display DeepCool device information.
EOF

cat > "$PKGDIR/DEBIAN/postinst" <<'EOP'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now deepcool-digital-dart.service 2>/dev/null || true
  rm -f /etc/systemd/system/deepcool-digital-dart.service
  systemctl daemon-reload || true
fi
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload || true
  udevadm trigger || true
fi
find /sys/class/powercap -name energy_uj -exec chmod a+r {} + 2>/dev/null || true
find /sys/class/powercap -name max_energy_range_uj -exec chmod a+r {} + 2>/dev/null || true
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications || true
fi
EOP

cat > "$PKGDIR/DEBIAN/prerm" <<'EOP'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl stop deepcool-digital-dart.service || true
  systemctl disable deepcool-digital-dart.service || true
  systemctl daemon-reload || true
fi
EOP

chmod 755 "$PKGDIR/DEBIAN/postinst" "$PKGDIR/DEBIAN/prerm"

mkdir -p "$OUTDIR"
echo "Building .deb..."
if command -v fakeroot >/dev/null 2>&1; then
  fakeroot dpkg-deb --build "$PKGDIR" "$OUTDIR/${PKGNAME}_${VERSION}_${ARCH}.deb"
else
  dpkg-deb --build "$PKGDIR" "$OUTDIR/${PKGNAME}_${VERSION}_${ARCH}.deb"
fi

echo "Package created at $OUTDIR/${PKGNAME}_${VERSION}_${ARCH}.deb"
