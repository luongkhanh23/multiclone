#!/usr/bin/env bash
set -euo pipefail

# Automated Theos + iOS SDK setup helper for macOS and Linux/WSL2 (Ubuntu/Debian).
THEOS_DIR="${THEOS:-$HOME/theos}"

echo "[MultiClone] Setting up Theos at: $THEOS_DIR"

OS_NAME="$(uname -s)"
if [ "$OS_NAME" = "Darwin" ]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "ERROR: Homebrew is required on macOS (https://brew.sh)." >&2
        exit 1
    fi
    brew list ldid >/dev/null 2>&1 || brew install ldid
    brew list dpkg >/dev/null 2>&1 || brew install dpkg
    brew list xz >/dev/null 2>&1 || brew install xz
elif [ "$OS_NAME" = "Linux" ]; then
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y build-essential fakeroot git perl curl xz-utils bzip2 dpkg dpkg-dev clang llvm lld python3
    fi
else
    echo "ERROR: Unsupported host OS '$OS_NAME'. Use macOS, Linux, WSL2, or GitHub Actions." >&2
    exit 1
fi

if [ ! -d "$THEOS_DIR" ]; then
    git clone --recursive https://github.com/theos/theos.git "$THEOS_DIR"
else
    echo "[MultiClone] Existing Theos installation found."
fi

# Ensure iOS SDK is present in $THEOS/sdks
mkdir -p "$THEOS_DIR/sdks"
if ! ls "$THEOS_DIR/sdks"/iPhoneOS*.sdk >/dev/null 2>&1; then
    echo "[MultiClone] Downloading patched Theos iOS SDK..."
    SDK_TARBALL="/tmp/theos-sdks.tar.xz"
    curl -fsSL "https://github.com/theos/sdks/archive/refs/heads/master.tar.gz" -o "$SDK_TARBALL"
    tar -xzf "$SDK_TARBALL" -C /tmp
    cp -R /tmp/sdks-master/iPhoneOS*.sdk "$THEOS_DIR/sdks/"
    rm -rf "$SDK_TARBALL" /tmp/sdks-master
fi

echo "[MultiClone] Theos environment ready. Export THEOS=$THEOS_DIR before running Scripts/build.sh"
