#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASES_DIR="$ROOT_DIR/Releases"
BUILD_LOG="$RELEASES_DIR/build.log"
THEOS_DIR="${THEOS:-$HOME/theos}"

mkdir -p "$RELEASES_DIR"

echo "=== MultiClone Rootless Build Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ") ===" | tee "$BUILD_LOG"

if [ ! -d "$THEOS_DIR" ]; then
    echo "ERROR: THEOS not found at '$THEOS_DIR'. Run ./Scripts/setup_theos.sh first." | tee -a "$BUILD_LOG"
    exit 1
fi

for cmd in make dpkg-deb python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required build tool '$cmd' is missing." | tee -a "$BUILD_LOG"
        exit 1
    fi
done

# Run pre-build static verification & unit tests
echo "[1/4] Running static & unit test suite..." | tee -a "$BUILD_LOG"
python3 "$ROOT_DIR/Tests/run_all_tests.py" 2>&1 | tee -a "$BUILD_LOG"

# Compile & package real rootless DEB with Theos
echo "[2/4] Compiling MultiCloneSpringBoard + MultiCloneManager (arm64 + arm64e, rootless)..." | tee -a "$BUILD_LOG"
cd "$ROOT_DIR"
export THEOS="$THEOS_DIR"
export THEOS_PACKAGE_SCHEME=rootless
make clean 2>&1 | tee -a "$BUILD_LOG"
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless 2>&1 | tee -a "$BUILD_LOG"

LATEST_DEB="$(ls -t "$ROOT_DIR"/packages/*.deb 2>/dev/null | head -n 1 || true)"
if [ -z "$LATEST_DEB" ] || [ ! -f "$LATEST_DEB" ]; then
    echo "ERROR: Build did not produce a .deb package in packages/." | tee -a "$BUILD_LOG"
    exit 1
fi

cp -f "$LATEST_DEB" "$RELEASES_DIR/MultiClone.deb"
cp -f "$LATEST_DEB" "$RELEASES_DIR/$(basename "$LATEST_DEB")"

echo "[3/4] Verifying built rootless DEB package..." | tee -a "$BUILD_LOG"
"$ROOT_DIR/Scripts/verify_package.sh" "$RELEASES_DIR/MultiClone.deb" 2>&1 | tee -a "$BUILD_LOG"

echo "[4/4] Computing SHA256 checksums..." | tee -a "$BUILD_LOG"
if command -v shasum >/dev/null 2>&1; then
    (cd "$RELEASES_DIR" && shasum -a 256 MultiClone.deb "$(basename "$LATEST_DEB")" > SHA256SUMS.txt)
else
    (cd "$RELEASES_DIR" && sha256sum MultiClone.deb "$(basename "$LATEST_DEB")" > SHA256SUMS.txt)
fi

cat "$RELEASES_DIR/SHA256SUMS.txt" | tee -a "$BUILD_LOG"
echo "=== MultiClone Build SUCCEEDED: $RELEASES_DIR/MultiClone.deb ===" | tee -a "$BUILD_LOG"
