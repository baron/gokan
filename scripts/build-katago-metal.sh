#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KATAGO_DIR="$ROOT_DIR/engine/KataGo"
BUILD_DIR="$ROOT_DIR/engine/build-katago-metal"

if [[ ! -d "$KATAGO_DIR/cpp" ]]; then
  printf 'KataGo checkout not found. Run scripts/fetch-katago.sh first.\n' >&2
  exit 1
fi

cmake -S "$KATAGO_DIR/cpp" \
  -B "$BUILD_DIR" \
  -G Ninja \
  -DUSE_BACKEND=METAL \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "$BUILD_DIR" --target katago

printf '\nBuilt: %s/katago\n' "$BUILD_DIR"
"$BUILD_DIR/katago" version || true
