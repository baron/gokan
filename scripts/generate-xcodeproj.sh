#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  printf 'xcodegen not found. Install it with: brew install xcodegen\n' >&2
  exit 1
fi

(cd "$ROOT_DIR/app" && xcodegen generate)
