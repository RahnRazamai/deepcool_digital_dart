Packaging notes for DeepCool Desktop App

This folder contains templates for creating distributable packages:

- `appimage/` - AppImage build recipe
- `arch/` - PKGBUILD for Arch Linux
- `debian/` - Debian packaging skeleton

Packages install the app, CLI daemon, desktop launcher, icon, and udev rule.
Persistent display updates are managed by the app through a per-user systemd
unit, so packages should not install or enable a system-wide daemon.
