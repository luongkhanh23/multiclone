#!/usr/bin/env bash
set -euo pipefail

DEB_PATH="${1:-}"
if [ -z "$DEB_PATH" ] || [ ! -f "$DEB_PATH" ]; then
    echo "Usage: $0 <path/to/MultiClone.deb>" >&2
    exit 2
fi

echo "[Verify] Inspecting DEB metadata: $DEB_PATH"
dpkg-deb -I "$DEB_PATH"

ARCH="$(dpkg-deb -f "$DEB_PATH" Architecture)"
if [ "$ARCH" != "iphoneos-arm64" ]; then
    echo "ERROR: Expected rootless Architecture 'iphoneos-arm64', got '$ARCH'" >&2
    exit 1
fi

echo "[Verify] Checking strict rootless filesystem layout (/var/jb/ only)..."
CONTENTS="$(dpkg-deb -c "$DEB_PATH")"
echo "$CONTENTS"

# Extract full path column (preserving spaces in paths like 'Application Support')
PATHS="$(echo "$CONTENTS" | sed -E 's/^([^ ]+ +){5}//')"

BAD_PATHS="$(echo "$PATHS" | grep -vE '^(\./?)?$|^(\./)?var/?$|^(\./)?var/jb(/.*)?$' || true)"
if [ -n "$BAD_PATHS" ]; then
    echo "ERROR: Non-rootless paths detected outside /var/jb/:" >&2
    echo "$BAD_PATHS" >&2
    exit 1
fi

if echo "$PATHS" | grep -q "var/jb/var/jb"; then
    echo "ERROR: Duplicate nested var/jb/var/jb path detected!" >&2
    exit 1
fi

# Confirm SpringBoard tweak, Manager app, Info.plist, icons, and defaults are present
for req in \
    "var/jb/Library/MobileSubstrate/DynamicLibraries/MultiClone.dylib" \
    "var/jb/Library/MobileSubstrate/DynamicLibraries/MultiClone.plist" \
    "var/jb/Applications/MultiCloneManager.app/MultiCloneManager" \
    "var/jb/Applications/MultiCloneManager.app/Info.plist" \
    "var/jb/Applications/MultiCloneManager.app/AppIcon60x60@2x.png" \
    "var/jb/Applications/MultiCloneManager.app/AppIcon60x60@3x.png" \
    "var/jb/Library/Application Support/MultiClone/auto-close-defaults.plist"; do
    echo "$PATHS" | grep -Fq "$req" || {
        echo "ERROR: Missing required rootless payload file: $req" >&2
        exit 1
    }
done

# Verify Mach-O slices if lipo or file is available
TMP_EXTRACT="$(mktemp -d)"
trap 'rm -rf "$TMP_EXTRACT"' EXIT
dpkg-deb -x "$DEB_PATH" "$TMP_EXTRACT"
dpkg-deb -e "$DEB_PATH" "$TMP_EXTRACT/DEBIAN"

for script in postinst prerm postrm; do
    if [ ! -x "$TMP_EXTRACT/DEBIAN/$script" ]; then
        echo "ERROR: DEBIAN/$script is missing or not executable" >&2
        exit 1
    fi
done

if command -v lipo >/dev/null 2>&1; then
    echo "[Verify] Checking Mach-O architectures..."
    lipo -info "$TMP_EXTRACT/var/jb/Library/MobileSubstrate/DynamicLibraries/MultiClone.dylib"
    lipo -info "$TMP_EXTRACT/var/jb/Applications/MultiCloneManager.app/MultiCloneManager"
fi

echo "[Verify] PASSED: Strict rootless DEB verified successfully."
