# Fedora RPM packaging

Build on x86_64 Fedora with the Flutter SDK (including Dart) on `PATH`.
The release workflow uses Fedora 43 so the package can also run on newer Fedora
versions without requiring libraries from the latest Fedora release.

Install the build dependencies:

```bash
sudo dnf install clang cmake ninja-build gcc-c++ pkgconf-pkg-config \
  gtk3-devel hidapi-devel libayatana-appindicator-gtk3-devel \
  rpm-build redhat-rpm-config desktop-file-utils patchelf
```

Build the app, daemon, and RPM:

```bash
bash packaging/rpm/build-release.sh
```

The version defaults to `pubspec.yaml`. Override it for a release:

```bash
bash packaging/rpm/build-release.sh --version v0.2.0
```

Prerelease versions such as `v0.2.0-rc.1` become `0.2.0~rc.1` in RPM so they
sort before the final release. Build metadata after `+` is omitted.

To package an existing Linux x64 release bundle and `build/deepcool-digital-dart`,
add `--skip-build`. Build those binaries on the oldest Fedora version you intend
to support; packaging newer binaries does not make them backward compatible.

The RPM is written to `packaging/out/`. Install it with:

```bash
sudo dnf install ./packaging/out/deepcool-desktop-*.x86_64.rpm
```

The package installs the full Flutter bundle, the CLI daemon, a desktop launcher,
an icon, and the udev rule for device access. HIDAPI and GTK/AppIndicator are
system dependencies resolved by DNF. Unplug and reconnect the display if device
access is still blocked after installation.

Open **DeepCool Digital Dart** and enable **Keep display running** to start
background updates. The app manages its own per-user systemd service; the RPM
does not install or enable a system-wide daemon.
