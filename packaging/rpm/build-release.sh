#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
version=""
skip_build=false

usage() {
  echo "Usage: $0 [--version VERSION] [--skip-build]"
  echo "Build a Fedora x86_64 RPM in packaging/out/."
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
  echo "ERROR: Build this package on x86_64 Fedora Linux." >&2
  exit 1
fi

for command in rpmbuild desktop-file-validate patchelf; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: $command is required. See packaging/rpm/README.md." >&2
    exit 1
  fi
done

if [[ -z "$version" ]]; then
  version="$(sed -n 's/^version: *//p' "$project_root/pubspec.yaml")"
fi
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*([-~+][0-9A-Za-z.+~-]+)?$ ]]; then
  echo "ERROR: Invalid package version: $version" >&2
  exit 1
fi
# RPM sorts prereleases with '~'; SemVer build metadata has no ordering meaning.
version="${version%%+*}"
version="${version//-/~}"

if [[ "$skip_build" == false ]]; then
  for command in flutter dart; do
    if ! command -v "$command" >/dev/null 2>&1; then
      echo "ERROR: $command is required on PATH. See packaging/rpm/README.md." >&2
      exit 1
    fi
  done
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
if [[ ! -x "$bundle/deepcool_desktop_app" ||
      ! -f "$bundle/lib/libflutter_linux_gtk.so" ||
      ! -f "$bundle/lib/libapp.so" ||
      ! -d "$bundle/data/flutter_assets" ||
      ! -x "$project_root/build/deepcool-digital-dart" ]]; then
  echo "ERROR: Release binaries are missing. Run without --skip-build to build them." >&2
  exit 1
fi

mkdir -p "$project_root/build" "$project_root/packaging/out"
rpm_dir="$(mktemp -d "$project_root/build/rpm.XXXXXX")"
trap 'rm -rf -- "$rpm_dir"' EXIT
source_dir="$rpm_dir/staging/deepcool-desktop-$version"
mkdir -p "$source_dir" "$rpm_dir/SOURCES" "$rpm_dir/tmp"
cp -a "$bundle" "$source_dir/flutter-bundle"
install -m755 "$project_root/build/deepcool-digital-dart" "$source_dir/"
install -m644 "$project_root/packaging/udev/99-deepcool-digital.rules" "$source_dir/"
install -m644 "$project_root/packaging/desktop/deepcool-desktop.desktop" "$source_dir/"
install -m644 "$project_root/LICENSE" "$project_root/NOTICE" "$project_root/README.md" "$source_dir/"
source "$project_root/packaging/icon-utils.sh"
install_256_icon "$project_root" "$source_dir/deepcool-desktop.png"

tar -C "$rpm_dir/staging" -czf "$rpm_dir/SOURCES/deepcool-desktop-$version.tar.gz" \
  "deepcool-desktop-$version"
rpmbuild -bb "$project_root/packaging/rpm/deepcool-desktop.spec" \
  --define "_topdir $rpm_dir" \
  --define "_tmppath $rpm_dir/tmp" \
  --define "package_version $version"

find "$rpm_dir/RPMS" -type f -name '*.rpm' \
  -exec install -m644 -t "$project_root/packaging/out" {} +
echo "RPM written to $project_root/packaging/out/"
