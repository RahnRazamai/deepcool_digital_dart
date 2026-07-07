# DeepCool Digital Desktop

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

On Windows:

```powershell
flutter pub get
flutter run -d windows
```

## Build

```bash
flutter build linux --release
```

On Windows:

```powershell
flutter build windows --release
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

For Windows, compile the daemon with an `.exe` extension:

```powershell
cd ..
dart compile exe bin/deepcool_digital_dart.dart -o build/deepcool-digital-dart.exe
```

Put `hidapi.dll` next to the app executable and daemon, or in `PATH`.

## App Flow

1. Save CPU, GPU, or PSU mode.
2. Turn on **Keep display running**.
3. Approve the admin prompt if device access needs to be installed.
4. Unplug and reconnect the display once if the app installs device access.

The top toggle starts a user-level background service with `--mode saved` on
Linux, or a Startup-folder launcher on Windows, so the display keeps working
after the GUI closes and after login.

PSU power is real when Linux exposes a PSU hwmon sensor. Otherwise the app shows
an estimated CPU + GPU power value when those sensors are readable.
