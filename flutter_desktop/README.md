# Deepcool Digital Linux

Flutter desktop app for DeepCool Digital displays.

Supported models include AG/AK air coolers, LD/LP/LQ/LS liquid coolers, and
CH/MORPHEUS cases listed in the main README.

Most users should install a packaged release from the main README. This folder
is mainly for development.

## Run From Source

```bash
flutter pub get
flutter run -d linux
```

## Build

```bash
flutter build linux --release
```

The release bundle is written to:

```text
flutter_desktop/build/linux/x64/release/bundle
```

The app also needs the background daemon if you want **Keep display running** to
work from a source checkout:

```bash
cd ..
dart compile exe bin/deepcool_digital_dart.dart -o build/deepcool-digital-dart
```

## App Flow

1. Save CPU, GPU, or PSU mode.
2. Turn on **Keep display running**.
3. Approve the admin prompt if device access needs to be installed.
4. Unplug and reconnect the display once if the app installs device access.

The top toggle starts a user-level background service with `--mode saved`, so
the display keeps working after the GUI closes and after login.
