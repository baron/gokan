#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_DIR="$ROOT_DIR/engine"
KATAGO_DIR="$ENGINE_DIR/KataGo"

mkdir -p "$ENGINE_DIR"

if [[ -d "$KATAGO_DIR/.git" ]]; then
  git -C "$KATAGO_DIR" fetch origin
  git -C "$KATAGO_DIR" status --short
else
  git clone https://github.com/lightvector/KataGo.git "$KATAGO_DIR"
fi

printf '\nKataGo checkout: %s\n' "$KATAGO_DIR"
git -C "$KATAGO_DIR" rev-parse --short HEAD
