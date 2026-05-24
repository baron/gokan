#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

missing=0

check() {
  local name="$1"
  local install_hint="$2"

  if command -v "$name" >/dev/null 2>&1; then
    printf '[ok] %s: %s\n' "$name" "$(command -v "$name")"
  else
    printf '[missing] %s (%s)\n' "$name" "$install_hint" >&2
    missing=1
  fi
}

check git 'install Xcode command line tools'
check cmake 'brew install cmake'
check ninja 'brew install ninja'
check xcrun 'install Xcode'
check swiftc 'install Xcode'

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

printf '\nToolchain looks ready.\n'
xcodebuild -version
swiftc --version | head -2
cmake --version | head -1
ninja --version
