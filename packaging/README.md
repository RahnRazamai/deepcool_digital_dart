Packaging notes for DeepCool Desktop App

This folder contains templates for creating distributable packages:

- `arch/` - PKGBUILD for Arch Linux
- `rpm/` - Fedora RPM spec and release build script
- `appimage/` - Linux x86_64 AppImage release build script
- `windows/` - Windows zip and installer build scripts

On Fedora, run `bash packaging/rpm/build-release.sh` to build an x86_64 RPM in
`packaging/out/`. See [rpm/README.md](rpm/README.md) for dependencies and options.

Build the AppImage on x86_64 Ubuntu 22.04 with the Flutter SDK on `PATH`:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev \
  libx11-dev libxi-dev libhidapi-dev desktop-file-utils curl file
bash packaging/appimage/build-release.sh
```

The script writes the AppImage to `packaging/out/`. Use `--version v1.2.3` to
set the filename version or `--skip-build` to package an existing release build
and CLI daemon. The script downloads appimagetool and the AppImage runtime.

Native Linux packages install the app, CLI daemon, desktop launcher, icon, and udev
rule. Persistent display updates are managed by the app through a per-user
systemd unit. The AppImage bundles the daemon and copies it to the user's data
directory when background updates are enabled.

Windows packages include the Flutter app, CLI daemon, headless sensor backend,
HIDAPI, and installer logic for the elevated scheduled sensor task.
