#!/usr/bin/env bash
set -euo pipefail

# Build a .deb package for DeepCool Desktop from the release bundle.
# Usage: ./make-deb.sh [version]

PKGNAME=deepcool-desktop
ARCH=amd64
VERSION=${1:-0.1.0}
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$REPO_ROOT/../flutter_desktop/build/linux/x64/release/bundle/deepcool_desktop_app"
OUTDIR="$REPO_ROOT/out"
PKGDIR="$OUTDIR/${PKGNAME}_${VERSION}_${ARCH}"

rm -rf "$PKGDIR"
mkdir -p "$PKGDIR/DEBIAN"
mkdir -p "$PKGDIR/usr/bin"
mkdir -p "$PKGDIR/etc/udev/rules.d"
mkdir -p "$PKGDIR/etc/systemd/system"
mkdir -p "$PKGDIR/usr/share/doc/$PKGNAME"

if [ ! -f "$BUNDLE" ]; then
  echo "Release binary not found at $BUNDLE"
  echo "Build with: (from repo root) flutter_desktop && flutter build linux --release"
  exit 1
fi

echo "Copying binary..."
cp "$BUNDLE" "$PKGDIR/usr/bin/deepcool-desktop"
chmod 755 "$PKGDIR/usr/bin/deepcool-desktop"

echo "Including udev rule and systemd unit..."
if [ -f "$REPO_ROOT/udev/99-deepcool-digital.rules" ]; then
  cp "$REPO_ROOT/udev/99-deepcool-digital.rules" "$PKGDIR/etc/udev/rules.d/99-deepcool-digital.rules"
fi
if [ -f "$REPO_ROOT/systemd/deepcool-digital-dart.service" ]; then
  cp "$REPO_ROOT/systemd/deepcool-digital-dart.service" "$PKGDIR/etc/systemd/system/deepcool-digital-dart.service"
fi

cat > "$PKGDIR/DEBIAN/control" <<EOF
Package: $PKGNAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: Your Name <you@example.com>
Depends: libc6 (>= 2.17), libhidapi0
Description: DeepCool Desktop GUI for CH170 devices
 A GTK desktop application to control and display DeepCool device information.
EOF

cat > "$PKGDIR/DEBIAN/postinst" <<'EOP'
#!/bin/sh
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  # Try to enable the system service if present
  if [ -f /etc/systemd/system/deepcool-digital-dart.service ]; then
    systemctl enable --now deepcool-digital-dart.service || true
  fi
fi
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload || true
  udevadm trigger || true
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
