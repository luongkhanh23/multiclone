#!/usr/bin/env python3
"""Read-only IPA preflight inspector for MultiClone (iOS 18.2 / Dopamine Rootless).

Inspects Bundle ID, Display Name, version, executable, icons, frameworks,
app extensions, URL schemes, provisioning profile XML, Mach-O architectures,
FairPlay DRM encryption flag (LC_ENCRYPTION_INFO_64), and embedded code-signature
entitlements (LC_CODE_SIGNATURE SuperBlob) directly from the IPA ZIP archive
without modifying, extracting, or executing the IPA.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path
from typing import Any

# Mach-O constants
MH_MAGIC_64 = 0xFEEDFACF
MH_MAGIC = 0xFEEDFACE
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA
CPU_TYPE_ARM = 12
CPU_TYPE_ARM64 = 0x0100000C
CPU_TYPE_X86_64 = 0x01000007
CPU_SUBTYPE_MASK = 0xFF000000
CPU_SUBTYPE_ARM64E = 2
LC_CODE_SIGNATURE = 0x1D
LC_ENCRYPTION_INFO_64 = 0x2C
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_ENTITLEMENTS = 0xFADE7171

THIRD_PARTY_SERVER_VERIFIED_PREFIXES = (
    "com.facebook.",
    "vn.com.vng.zalo",
    "com.zing.zalo",
    "com.zhiliaoapp.musically",
    "com.ss.iphone.ugc.",
)

PROTECTED_EXACT_BUNDLES = {
    "com.multiclone.manager",
    "com.opa334.dopamine",
    "org.coolstar.sileostore",
    "xyz.willy.zebra",
    "com.opa334.trollstore",
}


def _arch_name(cputype: int, cpusubtype: int) -> str:
    masked = cpusubtype & ~CPU_SUBTYPE_MASK
    if cputype == CPU_TYPE_ARM64:
        return "arm64e" if masked == CPU_SUBTYPE_ARM64E else "arm64"
    if cputype == CPU_TYPE_ARM:
        return "armv7"
    if cputype == CPU_TYPE_X86_64:
        return "x86_64"
    return f"cpu_{cputype}_{masked}"


def _parse_cs_entitlements(slice_data: bytes, sig_off: int, sig_size: int) -> dict[str, Any] | None:
    if sig_off + sig_size > len(slice_data) or sig_size < 12:
        return None
    cs = slice_data[sig_off : sig_off + sig_size]
    magic, _length, count = struct.unpack_from(">III", cs, 0)
    if magic != CSMAGIC_EMBEDDED_SIGNATURE or count > 128 or 12 + count * 8 > sig_size:
        return None
    for idx in range(count):
        _blob_type, blob_off = struct.unpack_from(">II", cs, 12 + idx * 8)
        if blob_off + 8 > sig_size:
            continue
        blob_magic, blob_len = struct.unpack_from(">II", cs, blob_off)
        if blob_magic == CSMAGIC_ENTITLEMENTS and blob_len > 8 and blob_off + blob_len <= sig_size:
            xml_bytes = cs[blob_off + 8 : blob_off + blob_len]
            try:
                parsed = plistlib.loads(xml_bytes)
                if isinstance(parsed, dict):
                    return parsed
            except Exception:
                return None
    return None


def inspect_macho_bytes(data: bytes) -> dict[str, Any]:
    res: dict[str, Any] = {
        "valid_macho": False,
        "architectures": [],
        "has_encryption_command": False,
        "is_fairplay_encrypted": False,
        "cryptid": 0,
        "has_code_signature": False,
        "entitlements": None,
    }
    if len(data) < 4:
        return res

    def _inspect_slice(sl: bytes) -> None:
        if len(sl) < 32:
            return
        magic = struct.unpack_from("<I", sl, 0)[0]
        if magic == MH_MAGIC:
            res["valid_macho"] = True
            cputype, cpusubtype = struct.unpack_from("<II", sl, 4)
            arch = _arch_name(cputype, cpusubtype)
            if arch not in res["architectures"]:
                res["architectures"].append(arch)
            return
        if magic != MH_MAGIC_64:
            return

        res["valid_macho"] = True
        cputype, cpusubtype, _filetype, ncmds, _sizeofcmds, _flags, _reserved = struct.unpack_from("<IIIIIII", sl, 4)
        arch = _arch_name(cputype, cpusubtype)
        if arch not in res["architectures"]:
            res["architectures"].append(arch)

        off = 32
        for _ in range(ncmds):
            if off + 8 > len(sl):
                break
            cmd, cmdsize = struct.unpack_from("<II", sl, off)
            if cmdsize < 8 or off + cmdsize > len(sl):
                break
            if cmd == LC_ENCRYPTION_INFO_64 and cmdsize >= 24:
                _cryptoff, _cryptsize, cryptid = struct.unpack_from("<III", sl, off + 8)
                res["has_encryption_command"] = True
                if cryptid != 0:
                    res["is_fairplay_encrypted"] = True
                    res["cryptid"] = cryptid
            elif cmd == LC_CODE_SIGNATURE and cmdsize >= 16:
                dataoff, datasize = struct.unpack_from("<II", sl, off + 8)
                res["has_code_signature"] = True
                if res["entitlements"] is None:
                    ents = _parse_cs_entitlements(sl, dataoff, datasize)
                    if ents is not None:
                        res["entitlements"] = ents
            off += cmdsize

    magic_be = struct.unpack_from(">I", data, 0)[0]
    if magic_be == FAT_MAGIC and len(data) >= 8:
        nfat = struct.unpack_from(">I", data, 4)[0]
        if nfat <= 16:
            pos = 8
            for _ in range(nfat):
                if pos + 20 > len(data):
                    break
                _ct, _cst, s_off, s_size, _align = struct.unpack_from(">IIIII", data, pos)
                if s_off + s_size <= len(data):
                    _inspect_slice(data[s_off : s_off + s_size])
                pos += 20
    else:
        _inspect_slice(data)

    return res


def _parse_mobileprovision(raw: bytes) -> dict[str, Any] | None:
    start = raw.find(b"<plist")
    end = raw.find(b"</plist>")
    if start < 0 or end < 0:
        return None
    try:
        parsed = plistlib.loads(raw[start : end + len(b"</plist>")])
        return parsed if isinstance(parsed, dict) else None
    except Exception:
        return None


def _is_cgbi_png(raw: bytes) -> bool:
    return len(raw) >= 16 and raw[:4] == b"\x89PNG" and raw[12:16] == b"CgBI"


def _evaluate_compatibility(report: dict[str, Any]) -> None:
    issues: list[dict[str, str]] = []
    blockers = 0
    warnings = 0

    app = report.get("app") or {}
    bid = app.get("bundle_id") or ""
    lower_bid = bid.lower()

    if not bid or "." not in bid:
        blockers += 1
        issues.append({
            "severity": "blocker",
            "code": "INVALID_BUNDLE_ID",
            "title": "Invalid Bundle Identifier",
            "detail": "CFBundleIdentifier is missing or not valid reverse-DNS.",
        })

    if lower_bid.startswith("com.apple.") or lower_bid in PROTECTED_EXACT_BUNDLES:
        blockers += 1
        issues.append({
            "severity": "blocker",
            "code": "PROTECTED_SYSTEM_APP",
            "title": "Protected System/Core Bundle",
            "detail": "MultiClone refuses to clone Apple system bundles or core jailbreak tools.",
        })

    macho = report.get("macho") or {}
    if macho.get("is_fairplay_encrypted"):
        blockers += 1
        issues.append({
            "severity": "blocker",
            "code": "FAIRPLAY_DRM_ENCRYPTED",
            "title": "FairPlay DRM Encrypted Binary (cryptid != 0)",
            "detail": "Executable is FairPlay encrypted. MultiClone does NOT bypass DRM.",
        })

    archs = macho.get("architectures") or []
    if archs and not ({"arm64", "arm64e"} & set(archs)):
        blockers += 1
        issues.append({
            "severity": "blocker",
            "code": "UNSUPPORTED_ARCH",
            "title": "Unsupported Architecture for iPhone 11",
            "detail": f"Expected arm64/arm64e; found {', '.join(archs)}.",
        })

    ents = report.get("entitlements")
    if isinstance(ents, dict):
        if ents.get("com.apple.security.application-groups"):
            warnings += 1
            issues.append({
                "severity": "warning",
                "code": "ENTITLEMENT_APP_GROUPS",
                "title": "App Groups Declared",
                "detail": "Changing Bundle ID may break App Group container isolation or sharing.",
            })
        if ents.get("keychain-access-groups"):
            warnings += 1
            issues.append({
                "severity": "warning",
                "code": "ENTITLEMENT_KEYCHAIN",
                "title": "Keychain Access Groups Declared",
                "detail": "Keychain access is tied to Team ID and entitlements.",
            })
        if "aps-environment" in ents:
            warnings += 1
            issues.append({
                "severity": "warning",
                "code": "ENTITLEMENT_PUSH",
                "title": "Push Notifications (APNs)",
                "detail": "APNs requires Apple-signed entitlements matching the registered Bundle ID.",
            })
        if ents.get("com.apple.developer.associated-domains"):
            warnings += 1
            issues.append({
                "severity": "warning",
                "code": "ENTITLEMENT_ASSOC_DOMAINS",
                "title": "Associated Domains",
                "detail": "Universal Links require original Team ID authorization.",
            })
    else:
        warnings += 1
        issues.append({
            "severity": "warning",
            "code": "ENTITLEMENTS_UNDETECTED",
            "title": "Entitlements Not Found in Signature",
            "detail": "No embedded LC_CODE_SIGNATURE entitlements or provisioning profile entitlements found.",
        })

    if report.get("extensions"):
        warnings += 1
        issues.append({
            "severity": "warning",
            "code": "EMBEDDED_EXTENSIONS",
            "title": f"{len(report['extensions'])} App Extension(s) Found",
            "detail": "Extensions require matching Bundle ID prefix and valid signing.",
        })

    if any(lower_bid.startswith(p) for p in THIRD_PARTY_SERVER_VERIFIED_PREFIXES):
        warnings += 1
        issues.append({
            "severity": "warning",
            "code": "THIRD_PARTY_SERVER_VERIFICATION",
            "title": "Third-Party Server Integrity Verification Likely",
            "detail": "Server-side attestation or bundle checks may restrict cloned instances. MultiClone does NOT bypass protection mechanisms.",
        })

    if blockers > 0:
        status = "incompatible"
        eligible = False
        reason = "Blocked due to DRM, unsupported architecture, or protected/invalid Bundle ID."
    elif warnings > 0:
        status = "warning"
        eligible = True
        reason = "Proceed only with authorized IPAs; review entitlement, extension, and server-verification warnings."
    else:
        status = "compatible"
        eligible = True
        reason = "Basic technical checks passed (no FairPlay DRM or restricted entitlements detected)."

    report["issues"] = issues
    report["clone_preflight"] = {
        "status": status,
        "eligible": eligible,
        "blocker_count": blockers,
        "warning_count": warnings,
        "reason": reason,
    }


def inspect(path: str | Path) -> dict[str, Any]:
    ipa_path = Path(path)
    if not ipa_path.is_file():
        raise ValueError(f"IPA not found: {ipa_path}")

    report: dict[str, Any] = {
        "file": str(ipa_path.resolve()),
        "valid_zip": False,
        "app": None,
        "icon": None,
        "macho": None,
        "extensions": [],
        "embedded_frameworks": [],
        "embedded_mobileprovision": False,
        "provisioning_summary": None,
        "entitlements": None,
        "warnings": [],
        "issues": [],
    }

    with zipfile.ZipFile(ipa_path) as z:
        names = z.namelist()
        report["valid_zip"] = True

        app_plists = [
            n for n in names
            if n.startswith("Payload/") and n.endswith(".app/Info.plist") and n.count("/") == 2
        ]
        if not app_plists:
            raise ValueError("No Payload/*.app/Info.plist found")

        info = plistlib.loads(z.read(app_plists[0]))
        app_prefix = app_plists[0][: -len("Info.plist")]
        exec_name = info.get("CFBundleExecutable")

        url_schemes: list[str] = []
        for item in info.get("CFBundleURLTypes", []):
            if isinstance(item, dict):
                url_schemes.extend(s for s in item.get("CFBundleURLSchemes", []) if isinstance(s, str))

        report["app"] = {
            "bundle_id": info.get("CFBundleIdentifier"),
            "display_name": info.get("CFBundleDisplayName") or info.get("CFBundleName"),
            "short_version": info.get("CFBundleShortVersionString"),
            "build_version": info.get("CFBundleVersion"),
            "executable": exec_name,
            "minimum_os": info.get("MinimumOSVersion"),
            "supported_platforms": info.get("CFBundleSupportedPlatforms", []),
            "url_schemes": url_schemes,
        }

        # Extensions, frameworks, provisioning, icon
        icon_candidates: list[tuple[int, str]] = []
        for n in names:
            if not n.startswith(app_prefix):
                continue
            rel = n[len(app_prefix):]
            if ".appex/Info.plist" in rel:
                try:
                    ep = plistlib.loads(z.read(n))
                    report["extensions"].append({
                        "path": rel,
                        "bundle_id": ep.get("CFBundleIdentifier"),
                        "name": ep.get("CFBundleDisplayName") or ep.get("CFBundleName"),
                        "extension_point": (ep.get("NSExtension") or {}).get("NSExtensionPointIdentifier"),
                    })
                except Exception:
                    report["warnings"].append(f"Could not parse extension plist: {n}")
            elif rel.startswith("Frameworks/") and (rel.endswith(".framework/Info.plist") or rel.endswith(".dylib")):
                fw_name = rel[len("Frameworks/"):].split("/")[0]
                if fw_name not in report["embedded_frameworks"]:
                    report["embedded_frameworks"].append(fw_name)
            elif rel == "embedded.mobileprovision":
                report["embedded_mobileprovision"] = True
                prov = _parse_mobileprovision(z.read(n))
                if prov:
                    report["provisioning_summary"] = {
                        "name": prov.get("Name"),
                        "team_name": prov.get("TeamName"),
                        "app_id_name": prov.get("AppIDName"),
                        "expiration_date": str(prov.get("ExpirationDate")) if prov.get("ExpirationDate") else None,
                    }
                    if isinstance(prov.get("Entitlements"), dict):
                        report["entitlements"] = prov["Entitlements"]
            elif "/" not in rel and rel.lower().endswith(".png") and ("appicon" in rel.lower() or "icon" in rel.lower()):
                icon_candidates.append((z.getinfo(n).file_size, n))

        if icon_candidates:
            icon_candidates.sort(reverse=True)
            best_size, best_path = icon_candidates[0]
            raw_icon = z.read(best_path)
            report["icon"] = {
                "path": best_path,
                "size_bytes": best_size,
                "cgbi_encoded": _is_cgbi_png(raw_icon),
            }

        # Mach-O inspection (architectures, DRM cryptid, LC_CODE_SIGNATURE entitlements)
        if exec_name and (app_prefix + exec_name) in names:
            macho_info = inspect_macho_bytes(z.read(app_prefix + exec_name))
            report["macho"] = {k: v for k, v in macho_info.items() if k != "entitlements"}
            if macho_info.get("entitlements") is not None:
                report["entitlements"] = macho_info["entitlements"]

    _evaluate_compatibility(report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="MultiClone read-only IPA preflight inspector")
    parser.add_argument("ipa", help="Path to .ipa archive")
    parser.add_argument("--json", dest="out", help="Write JSON report to file")
    args = parser.parse_args()
    try:
        data = inspect(args.ipa)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    rendered = json.dumps(data, ensure_ascii=False, indent=2, default=str)
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
