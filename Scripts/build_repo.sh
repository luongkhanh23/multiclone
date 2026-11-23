#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="${1:-$ROOT_DIR/Releases}"
OUT_DIR="${2:-$ROOT_DIR/Repository}"

python3 "$ROOT_DIR/Scripts/build_repo.py" "$PKG_DIR" "$OUT_DIR"
echo "[MultiClone] Sileo APT repository updated at $OUT_DIR (ready for GitHub Pages)."
