#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
version=""
skip_build=false

usage() {
  echo "Usage: $0 [--version VERSION] [--skip-build]"
  echo "Build an x86_64 Linux AppImage in packaging/out/."
  echo "--skip-build packages the existing Flutter release bundle and CLI daemon."
}

while (($#)); do
  case "$1" in
    --version)
      if (($# < 2)); then
        usage >&2
        exit 1
      fi
      version="$2"
      shift 2
      ;;
    --skip-build)
      skip_build=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "ERROR: Build this AppImage on x86_64 Linux." >&2
  exit 1
fi

if [[ -z "$version" ]]; then
  version="$(sed -n 's/^version: *//p' "$project_root/pubspec.yaml")"
fi
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.+-]+)?$ ]]; then
  echo "ERROR: Invalid package version: $version" >&2
  exit 1
fi

required_tools=(curl desktop-file-validate file pkg-config)
if [[ "$skip_build" == false ]]; then
  required_tools+=(flutter dart)
fi
for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" >/dev/null; then
    echo "ERROR: $tool is required. See packaging/README.md." >&2
    exit 1
  fi
done

if [[ "$skip_build" == false ]]; then
  (
    cd "$project_root/flutter_desktop"
    flutter pub get
    flutter build linux --release
  )
  (
    cd "$project_root"
    mkdir -p build
    dart pub get
    dart compile exe bin/deepcool_digital_dart.dart -o build/deepcool-digital-dart
  )
fi

bundle="$project_root/flutter_desktop/build/linux/x64/release/bundle"
daemon="$project_root/build/deepcool-digital-dart"
if [[ ! -x "$bundle/deepcool_desktop_app" ||
      ! -f "$bundle/lib/libflutter_linux_gtk.so" ||
      ! -f "$bundle/lib/libapp.so" ||
      ! -f "$bundle/lib/libcnativeapi.so" ||
      ! -d "$bundle/data/flutter_assets" || ! -x "$daemon" ]]; then
  echo "ERROR: Release binaries are missing. Run without --skip-build to build them." >&2
  exit 1
fi

mkdir -p "$project_root/build" "$project_root/packaging/out"
staging="$(mktemp -d "$project_root/build/appimage.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
appdir="$staging/DeepCool.AppDir"
bindir="$appdir/usr/bin"
mkdir -p "$bindir"
cp -a "$bundle/." "$bindir/"
install -m755 "$daemon" "$bindir/"

# Bundle HIDAPI alongside Flutter's native assets. GTK and X11 come from the host.
hidapi_libdir="$(pkg-config --variable=libdir hidapi-hidraw)"
install -m644 "$hidapi_libdir/libhidapi-hidraw.so.0" "$bindir/lib/"

install -m755 "$project_root/packaging/appimage/AppRun" "$appdir/AppRun"
install -m644 "$project_root/packaging/desktop/deepcool-desktop.desktop" "$appdir/"
desktop-file-validate "$appdir/deepcool-desktop.desktop"
ln -s ../../AppRun "$bindir/deepcool-desktop"
source "$project_root/packaging/icon-utils.sh"
install_256_icon "$project_root" "$appdir/deepcool-desktop.png"
ln -s deepcool-desktop.png "$appdir/.DirIcon"
install -Dm644 "$project_root/packaging/udev/99-deepcool-digital.rules" \
  "$appdir/usr/lib/udev/rules.d/99-deepcool-digital.rules"
install -Dm644 -t "$appdir/usr/share/doc/deepcool-desktop" "$project_root/LICENSE" "$project_root/NOTICE"

tool="$staging/appimagetool"
runtime="$staging/runtime-x86_64"
curl -fsSL --retry 3 -o "$tool" \
  https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
curl -fsSL --retry 3 -o "$runtime" \
  https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64
sha256sum --check <<EOF
ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0  $tool
2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d  $runtime
EOF
chmod +x "$tool"

filename="deepcool-desktop-$version-x86_64.AppImage"
ARCH=x86_64 VERSION="$version" APPIMAGE_EXTRACT_AND_RUN=1 \
  "$tool" --no-appstream --runtime-file "$runtime" "$appdir" "$staging/$filename"
test -x "$staging/$filename"
mv -f "$staging/$filename" "$project_root/packaging/out/$filename"
echo "AppImage written to packaging/out/$filename"
