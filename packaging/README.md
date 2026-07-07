Packaging notes for DeepCool Desktop App

This folder contains templates for creating distributable packages:

- `arch/` - PKGBUILD for Arch Linux
- `windows/` - Windows zip and installer build scripts

Linux packages install the app, CLI daemon, desktop launcher, icon, and udev
rule. Persistent display updates are managed by the app through a per-user
systemd unit, so Linux packages should not install or enable a system-wide
daemon.

Windows packages include the Flutter app, CLI daemon, headless sensor backend,
HIDAPI, and installer logic for the elevated scheduled sensor task.
