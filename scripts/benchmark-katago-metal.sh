#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KATAGO_BIN="$ROOT_DIR/engine/build-katago-metal/katago"

if [[ $# -lt 2 ]]; then
  printf 'Usage: %s path/to/model.bin.gz path/to/config.cfg\n' "$0" >&2
  exit 2
fi

MODEL_PATH="$1"
CONFIG_PATH="$2"

if [[ ! -x "$KATAGO_BIN" ]]; then
  printf 'KataGo Metal binary not found. Run scripts/build-katago-metal.sh first.\n' >&2
  exit 1
fi

"$KATAGO_BIN" benchmark -model "$MODEL_PATH" -config "$CONFIG_PATH"
