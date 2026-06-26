# DeepCool Digital Dart

Linux desktop app for DeepCool Digital displays.

Supported models:

- Air coolers: **AG300 DIGITAL**, **AG400 DIGITAL**, **AG500 DIGITAL**,
  **AG620 DIGITAL**, **AK400 DIGITAL**, **AK400 DIGITAL PRO**,
  **AK400 G2 DIGITAL NYX**, **AK500 DIGITAL**, **AK500 DIGITAL PRO**,
  **AK500 G2 DIGITAL NYX**, **AK500S DIGITAL**, **AK620 DIGITAL**,
  **AK620 DIGITAL PRO**, **AK620 G2 DIGITAL NYX**,
  **AK700 DIGITAL NYX**, **ASSASSIN IV VC VISION**
- Liquid coolers: **LD240**, **LD360**, **LP240**, **LP360**, **LQ240**,
  **LQ360**, **LS520 SE DIGITAL**, **LS720 SE DIGITAL**
- Cases: **CH170 DIGITAL**, **CH270 DIGITAL**, **CH360 DIGITAL**,
  **CH510 MESH DIGITAL**, **CH560 DIGITAL**, **CH690 DIGITAL**,
  **MORPHEUS**

Use it to choose what the display shows: CPU, GPU, or PSU mode. After you save
a mode, the app can keep the display running in the background, even after you
close the window.

Some devices only support CPU display modes. The app auto-detects the connected
model and uses the right packet format for that hardware.

This is an unofficial GPLv3 Dart port of
[`deepcool-digital-linux`](https://github.com/Nortank12/deepcool-digital-linux).

## Download

Get the latest release from GitHub Releases.

Choose the package for your distro:

| System | Recommended download |
| --- | --- |
| Ubuntu / Debian | `.deb` |
| Arch Linux | `.pkg.tar.zst` |
| SteamOS | `.AppImage` |
| Bazzite | `.AppImage` |
| Other Linux | `.AppImage` |

## Install

### Ubuntu / Debian

```bash
sudo apt install ./deepcool-desktop_*.deb
```

### Arch Linux

```bash
sudo pacman -U deepcool-desktop-*.pkg.tar.zst
```

### SteamOS / Bazzite / Other Linux

```bash
chmod +x Deepcool-Digital-Linux*.AppImage
./Deepcool-Digital-Linux*.AppImage
```

On SteamOS, run it from Desktop Mode.

## First Use

1. Open **Deepcool Digital Linux**.
2. Pick **CPU**, **GPU**, or **PSU** from the left side.
3. Click **Save ... view to display**.
4. Turn on **Keep display running** at the top of the app.
5. Approve the admin prompt if it appears.
6. If the app installs device access, unplug and reconnect the display once.

After that, the saved display mode should keep running after you close the app
and after you sign in again.

## How It Works

The GUI is only for choosing the display mode.

The **Keep display running** toggle starts a small background daemon that keeps
sending updates to the display. That is why the screen can keep working without
the app window being open.

PSU readings are shown when Linux exposes a real PSU sensor through hwmon. If
no PSU sensor is available, the PSU page and supported PSU display modes fall
back to an estimated **CPU + GPU power** value when those sensors are readable.
That estimate excludes motherboard, drives, fans, and PSU conversion losses.

## Troubleshooting

### The display stops when I close the app

Turn on **Keep display running**. If you are running from source instead of an
installed package, build the daemon first:

```bash
dart compile exe bin/deepcool_digital_dart.dart -o build/deepcool-digital-dart
```

### Linux is blocking access to the display

Turn on **Keep display running** and approve the admin prompt. Then unplug and
reconnect the display once.

Manual fallback:

```bash
sudo cp packaging/udev/99-deepcool-digital.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### The display flickers between modes

This usually means an old system service is still running and sending a second
mode to the display. You do not need to clean the project. Turn **Keep display
running** off and on once, or run:

```bash
systemctl --user stop deepcool-digital-dart.service
sudo systemctl disable --now deepcool-digital-dart.service
sudo rm -f /etc/systemd/system/deepcool-digital-dart.service
sudo systemctl daemon-reload
```

### The app says HIDAPI is missing

Install HIDAPI for your distro:

```bash
# Ubuntu / Debian
sudo apt install libhidapi-hidraw0

# Arch
sudo pacman -S hidapi

# Fedora
sudo dnf install hidapi
```

## Development

Run the app from source:

```bash
cd flutter_desktop
flutter pub get
flutter run -d linux
```

Build release binaries:

```bash
cd flutter_desktop
flutter build linux --release
cd ..
dart compile exe bin/deepcool_digital_dart.dart -o build/deepcool-digital-dart
```

Useful checks:

```bash
dart format .
dart analyze lib bin
flutter analyze
flutter test
```

## Project Layout

- `flutter_desktop/` - Flutter desktop app
- `lib/` and `bin/` - shared Dart library and CLI daemon
- `packaging/` - AppImage, Debian, and Arch packaging

## License

GPL-3.0. See `LICENSE` and `NOTICE`.
