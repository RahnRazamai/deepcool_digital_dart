# Deepcool Digital Linux

This is a Flutter desktop app that connects to the `deepcool_digital_dart` package to display CPU and GPU monitoring information and send HID commands to supported devices.

Run locally (development):

```bash
cd flutter_desktop
flutter pub get
flutter run -d linux
```

Build a release bundle (Linux):

```bash
cd flutter_desktop
flutter build linux --release
# bundle located at flutter_desktop/build/linux/x64/release/bundle
```

Run the built binary (from bundle):

```bash
cd flutter_desktop/build/linux/x64/release/bundle
./deepcool_desktop_app
```

Autostart (user-level):
- Use the Settings page in the app to set the daemon executable path and toggle user autostart.
- The app writes a systemd user unit to `~/.config/systemd/user/deepcool-digital-dart.service` and calls `systemctl --user enable --now`.

Install system service (system-wide):
- From the Settings page you can "Install systemd service (requires sudo)" which copies a unit to `/etc/systemd/system/` and enables it.

Udev rule (device access):
- A sample udev rule is provided at `packaging/udev/99-deepcool-digital.rules`.
- Install with:

```bash
sudo cp packaging/udev/99-deepcool-digital.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger
```

Packaging helpers:
- AppImage: `packaging/appimage/make-appimage.sh` — requires `linuxdeploy` and `appimagetool`.
- Debian: skeleton in `packaging/debian/` (use `dpkg-deb` / `debhelper` to build).
- Arch: `packaging/arch/PKGBUILD` is a template for `makepkg`.

Quick packaging script (examples):

```bash
# AppImage (after building release bundle)
bash packaging/appimage/make-appimage.sh

# Arch/Deb templates
bash packaging/make-packages.sh arch
bash packaging/make-packages.sh deb
```

Notes and troubleshooting:
- HID access requires `libhidapi` installed on the target system.
- If the app cannot start the daemon, open `Settings` and set the correct `daemon executable path` (e.g. `/usr/bin/deepcool-digital-dart`).
- The Settings page can also install the udev rule and systemd unit (prompts for sudo/pkexec when needed).
