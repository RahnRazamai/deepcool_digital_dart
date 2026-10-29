%{!?package_version:%global package_version 0.1.0}

# Flutter ships prebuilt binaries and private plugin libraries. Keep their
# symbols intact and do not advertise the private libraries as system providers.
%global debug_package %{nil}
%global __strip /bin/true
%global __provides_exclude_from ^%{_libdir}/deepcool-desktop/.*$
%global __requires_exclude ^lib(app|flutter_linux_gtk|[^/]*_plugin)[.]so.*$

Name:           deepcool-desktop
Version:        %{package_version}
Release:        1%{?dist}
Summary:        Desktop app for DeepCool Digital displays
License:        GPL-3.0-only
URL:            https://github.com/RahnRazamai/deepcool_digital_dart
Source0:        %{name}-%{version}.tar.gz
ExclusiveArch:  x86_64

BuildRequires:  desktop-file-utils
BuildRequires:  patchelf
Requires:       gtk3
Requires:       hidapi
Requires:       libayatana-appindicator-gtk3
Requires:       systemd
Requires:       polkit
Requires(post): systemd-udev
Requires(postun): systemd-udev

%description
Choose CPU, GPU, or PSU display modes for supported DeepCool Digital devices.
Includes the Flutter desktop app and CLI daemon. The app manages background
display updates through a per-user systemd service.

%prep
%setup -q

%build
# The release script builds the Flutter bundle and Dart daemon before packaging.

%install
install -dm755 "%{buildroot}%{_libdir}/%{name}"
cp -a flutter-bundle/. "%{buildroot}%{_libdir}/%{name}/"
chmod 755 "%{buildroot}%{_libdir}/%{name}/deepcool_desktop_app"
# Flutter copies plugin build outputs with SDK paths in their RUNPATH. Resolve
# the engine beside each plugin instead, so no build-machine paths are shipped.
find "%{buildroot}%{_libdir}/%{name}/lib" -maxdepth 1 -type f -name '*_plugin.so' \
    -exec patchelf --set-rpath '$ORIGIN' {} \;

install -Dm755 /dev/stdin "%{buildroot}%{_bindir}/deepcool-desktop" <<'EOF'
#!/usr/bin/bash
set -e
APPDIR="%{_libdir}/deepcool-desktop"
cd "$APPDIR"
export LD_LIBRARY_PATH="$APPDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$APPDIR/deepcool_desktop_app" "$@"
EOF

install -Dm755 deepcool-digital-dart "%{buildroot}%{_bindir}/deepcool-digital-dart"
install -Dm644 99-deepcool-digital.rules "%{buildroot}%{_prefix}/lib/udev/rules.d/99-deepcool-digital.rules"
install -Dm644 deepcool-desktop.desktop "%{buildroot}%{_datadir}/applications/deepcool-desktop.desktop"
install -Dm644 deepcool-desktop.png "%{buildroot}%{_datadir}/icons/hicolor/256x256/apps/deepcool-desktop.png"

%check
desktop-file-validate "%{buildroot}%{_datadir}/applications/deepcool-desktop.desktop"

%post
/usr/bin/udevadm control --reload-rules >/dev/null 2>&1 || :
/usr/bin/udevadm trigger --subsystem-match=hidraw --action=change >/dev/null 2>&1 || :

%postun
if [ "$1" -eq 0 ]; then
    /usr/bin/udevadm control --reload-rules >/dev/null 2>&1 || :
fi

%files
%license LICENSE NOTICE
%doc README.md
%{_bindir}/deepcool-desktop
%{_bindir}/deepcool-digital-dart
%{_libdir}/%{name}/
%{_prefix}/lib/udev/rules.d/99-deepcool-digital.rules
%{_datadir}/applications/deepcool-desktop.desktop
%{_datadir}/icons/hicolor/256x256/apps/deepcool-desktop.png

%changelog
* Fri Oct 30 2026 DeepCool Digital Dart contributors - 0.1.0-1
- Restore Fedora RPM packaging with the GUI, daemon, and device access rule.
