Packaging notes for DeepCool Desktop App

This folder contains templates for creating distributable packages:

- `appimage/` - AppImage build recipe
- `arch/` - PKGBUILD for Arch Linux
- `debian/` - Debian packaging skeleton

Each template includes a systemd unit and udev rule example. Adjust `ExecStart`
paths to point to the installed `deepcool-digital-dart` binary.
