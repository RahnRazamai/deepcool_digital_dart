#!/usr/bin/env bash

install_256_icon() {
  local project_root="$1"
  local destination="$2"
  local exact_source="$project_root/flutter_desktop/appdir/usr/share/icons/hicolor/256x256/apps/deepcool-desktop.png"
  local high_res_source="$project_root/flutter_desktop/assets/app-icon.png"

  if [ -f "$exact_source" ]; then
    echo "Using 256x256 icon: $exact_source"
    install -Dm644 "$exact_source" "$destination"
  elif [ -f "$high_res_source" ]; then
    echo "Resizing app icon to 256x256: $high_res_source"
    mkdir -p "$(dirname "$destination")"
    if command -v magick >/dev/null 2>&1; then
      magick "$high_res_source" -background none -resize 256x256 -gravity center -extent 256x256 "$destination"
    elif command -v convert >/dev/null 2>&1; then
      convert "$high_res_source" -background none -resize 256x256 -gravity center -extent 256x256 "$destination"
    else
      echo "ERROR: No 256x256 icon found and ImageMagick is not available to resize $high_res_source" >&2
      return 1
    fi
  else
    echo "ERROR: App icon not found at $exact_source or $high_res_source" >&2
    return 1
  fi

  if command -v identify >/dev/null 2>&1; then
    local geometry
    geometry="$(identify -format '%wx%h' "$destination" 2>/dev/null || true)"
    if [ "$geometry" != "256x256" ]; then
      echo "ERROR: Installed icon $destination must be 256x256, got ${geometry:-unknown}" >&2
      return 1
    fi
  fi
}
