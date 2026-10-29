#!/usr/bin/env bash
set -euo pipefail

echo "This script lists packaging steps for Arch Linux, Fedora, and Windows."

echo "Arch: build PKG (run in an Arch environment or use makepkg)."
echo "Fedora: bash packaging/rpm/build-release.sh (run on x86_64 Fedora)."
echo "Windows: run packaging/windows/build-release.ps1 on Windows."

echo "Templates are in packaging/. Edit paths and run appropriate tools on target platform."
