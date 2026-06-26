# DeepCool Digital Dart

A Linux-first GUI app for the DeepCool CH170 DIGITAL case display.

This repository contains:

- `flutter_desktop/`: Flutter Linux desktop app and packaging helpers.
- `lib/` and `bin/`: shared Dart library code and a CLI entrypoint.
- `packaging/`: AppImage, Debian, and Arch packaging support.

This is an unofficial GPLv3 Dart port of `deepcool-digital-linux`.
Upstream reference: https://github.com/Nortank12/deepcool-digital-linux

## GUI-first Quick Start

The recommended way to use this project is with the desktop app in
`flutter_desktop/`.

```bash
cd flutter_desktop
flutter pub get
flutter run -d linux
```

Build a release bundle for Linux:

```bash
cd flutter_desktop
flutter build linux --release
```

Run the built desktop app:

```bash
cd flutter_desktop/build/linux/x64/release/bundle
./deepcool_desktop_app
```

## What the desktop app does

- displays CPU and GPU telemetry
- sends HID reports to DeepCool CH170 and compatible devices
- lets you configure the daemon executable path
- installs user/systemd autostart units
- installs a udev rule for rootless HID device access

For more details, see `flutter_desktop/README.md`.

## Requirements

- Linux
- Flutter SDK for the desktop app
- HIDAPI runtime library:
  - Arch: `sudo pacman -S hidapi`
  - Debian/Ubuntu: `sudo apt install libhidapi-hidraw0`
  - Fedora: `sudo dnf install hidapi`
- Root access, or a udev rule that allows your user to write to the DeepCool
  HID raw device

NVIDIA GPU mode uses `libnvidia-ml.so` through Dart FFI when available. AMD
and Intel GPU modes use Linux sysfs.

## Udev rule

Install the sample rule from `packaging/udev/99-deepcool-digital.rules`:

```bash
sudo cp packaging/udev/99-deepcool-digital.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## CLI fallback

If you prefer a headless tool instead of the GUI, the root `bin/` entrypoint
uses the same shared package code.

```bash
cd /home/rahngamingstudio/development/deepcool_digital_dart
dart run bin/deepcool_digital_dart.dart --help
```

Recommended CLI examples:

```bash
dart run bin/deepcool_digital_dart.dart --dry-run
sudo dart run bin/deepcool_digital_dart.dart --mode cpu_freq
sudo dart run bin/deepcool_digital_dart.dart --mode gpu
sudo dart run bin/deepcool_digital_dart.dart --mode auto
```

## Optional native executable (Linux)

Dart uses `dart compile exe` to build a native executable on all platforms, including Linux. The output file does not need a `.exe` extension on Linux.

Compile a standalone Linux executable from the root package:

```bash
dart compile exe bin/deepcool_digital_dart.dart -o deepcool-digital-dart
sudo ./deepcool-digital-dart --mode cpu_freq
```

## Systemd service example

After installing the binary somewhere stable, create
`/etc/systemd/system/deepcool-digital-dart.service`:

```ini
[Unit]
Description=DeepCool Digital Dart CH170
After=multi-user.target

[Service]
ExecStart=/home/rahngamingstudio/development/deepcool_digital_dart/deepcool-digital-dart --mode auto
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now deepcool-digital-dart
```

## Development checks

```bash
dart format .
dart analyze
dart run bin/deepcool_digital_dart.dart --dry-run
```

## License

GPL-3.0. See `LICENSE` and `NOTICE`.
