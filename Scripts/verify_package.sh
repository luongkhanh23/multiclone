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

BAD_PATHS="$(echo "$CONTENTS" | awk '{print $6}' | grep -vE '^\./$|^\./var/$|^\./var/jb/' || true)"
if [ -n "$BAD_PATHS" ]; then
    echo "ERROR: Non-rootless paths detected outside /var/jb/:" >&2
    echo "$BAD_PATHS" >&2
    exit 1
fi

# Confirm both SpringBoard tweak and Manager app are present
echo "$CONTENTS" | grep -q "var/jb/Library/MobileSubstrate/DynamicLibraries/MultiClone.dylib" || {
    echo "ERROR: Missing MultiClone.dylib in rootless DynamicLibraries" >&2
    exit 1
}
echo "$CONTENTS" | grep -q "var/jb/Library/MobileSubstrate/DynamicLibraries/MultiClone.plist" || {
    echo "ERROR: Missing MultiClone.plist filter" >&2
    exit 1
}
echo "$CONTENTS" | grep -q "var/jb/Applications/MultiCloneManager.app/MultiCloneManager" || {
    echo "ERROR: Missing MultiCloneManager.app executable" >&2
    exit 1
}

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
