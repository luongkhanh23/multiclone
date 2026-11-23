#!/usr/bin/env python3
"""Unit tests for IPAInspector: Mach-O arm64/arm64e, FairPlay DRM detection,
embedded LC_CODE_SIGNATURE entitlements, extensions, frameworks, and third-party warnings."""

import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ipa_inspect", ROOT / "Source" / "CLI" / "ipa_inspect.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def build_synthetic_macho_64(cputype=0x0100000C, cpusubtype=0, cryptid=0, entitlements_dict=None) -> bytes:
    """Builds a minimal valid 64-bit Mach-O binary with LC_ENCRYPTION_INFO_64 and optional LC_CODE_SIGNATURE."""
    cmds = bytearray()
    ncmds = 0

    # LC_ENCRYPTION_INFO_64 (cmd=0x2C, cmdsize=24)
    cmds += struct.pack("<IIIII I", 0x2C, 24, 0, 0, cryptid, 0)
    ncmds += 1

    sig_blob = b""
    if entitlements_dict is not None:
        xml_bytes = plistlib.dumps(entitlements_dict, fmt=plistlib.FMT_XML)
        # Entitlements blob: magic (0xfade7171), length (8 + len)
        ent_blob = struct.pack(">II", 0xFADE7171, 8 + len(xml_bytes)) + xml_bytes
        # SuperBlob: magic (0xfade0cc0), length, count=1, index[0]=(type=5, offset=20)
        total_len = 12 + 8 + len(ent_blob)
        sig_blob = struct.pack(">IIIII", 0xFADE0CC0, total_len, 1, 5, 20) + ent_blob
        # LC_CODE_SIGNATURE (cmd=0x1D, cmdsize=16): dataoff will be placed right after header + cmds
        sig_offset = 32 + len(cmds) + 16
        cmds += struct.pack("<IIII", 0x1D, 16, sig_offset, len(sig_blob))
        ncmds += 1

    header = struct.pack("<IIIIIIII", 0xFEEDFACF, cputype, cpusubtype, 2, ncmds, len(cmds), 0, 0)
    return bytes(header + cmds + sig_blob)


def create_test_ipa(dest: Path, bundle_id: str, cryptid=0, entitlements=None, cputype=0x0100000C, with_ext=False) -> Path:
    info_plist = plistlib.dumps({
        "CFBundleIdentifier": bundle_id,
        "CFBundleDisplayName": "Test App",
        "CFBundleShortVersionString": "2.1.0",
        "CFBundleVersion": "210",
        "CFBundleExecutable": "TestApp",
        "MinimumOSVersion": "15.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "CFBundleURLTypes": [{"CFBundleURLSchemes": ["testapp"]}],
    })
    macho = build_synthetic_macho_64(cputype=cputype, cryptid=cryptid, entitlements_dict=entitlements)

    with zipfile.ZipFile(dest, "w") as z:
        z.writestr("Payload/TestApp.app/Info.plist", info_plist)
        z.writestr("Payload/TestApp.app/TestApp", macho)
        z.writestr("Payload/TestApp.app/AppIcon60x60@3x.png", b"\x89PNG\r\n\x1a\n" + b"\x00" * 16)
        z.writestr("Payload/TestApp.app/Frameworks/CoreKit.framework/Info.plist", plistlib.dumps({"CFBundleIdentifier": "com.test.corekit"}))
        if with_ext:
            z.writestr(
                "Payload/TestApp.app/PlugIns/Share.appex/Info.plist",
                plistlib.dumps({
                    "CFBundleIdentifier": f"{bundle_id}.Share",
                    "CFBundleDisplayName": "Share",
                    "NSExtension": {"NSExtensionPointIdentifier": "com.apple.share-services"},
                }),
            )
    return dest


class IPAInspectorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def test_compatible_unencrypted_arm64_ipa(self):
        ipa = create_test_ipa(
            Path(self.tmp.name) / "clean.ipa",
            bundle_id="com.example.ownedapp",
            cryptid=0,
            entitlements={"get-task-allow": True},
        )
        rep = mod.inspect(ipa)
        self.assertTrue(rep["valid_zip"])
        self.assertEqual(rep["app"]["bundle_id"], "com.example.ownedapp")
        self.assertEqual(rep["macho"]["architectures"], ["arm64"])
        self.assertFalse(rep["macho"]["is_fairplay_encrypted"])
        self.assertEqual(rep["entitlements"]["get-task-allow"], True)
        self.assertEqual(rep["embedded_frameworks"], ["CoreKit.framework"])
        self.assertEqual(rep["clone_preflight"]["status"], "compatible")
        self.assertTrue(rep["clone_preflight"]["eligible"])

    def test_fairplay_drm_encrypted_ipa_is_blocked(self):
        ipa = create_test_ipa(
            Path(self.tmp.name) / "drm.ipa",
            bundle_id="com.example.drmapp",
            cryptid=1,
            entitlements={"get-task-allow": False},
        )
        rep = mod.inspect(ipa)
        self.assertTrue(rep["macho"]["is_fairplay_encrypted"])
        self.assertEqual(rep["clone_preflight"]["status"], "incompatible")
        self.assertFalse(rep["clone_preflight"]["eligible"])
        codes = {i["code"] for i in rep["issues"]}
        self.assertIn("FAIRPLAY_DRM_ENCRYPTED", codes)

    def test_entitlements_and_third_party_warnings(self):
        ipa = create_test_ipa(
            Path(self.tmp.name) / "social.ipa",
            bundle_id="com.facebook.Facebook",
            cryptid=0,
            entitlements={
                "com.apple.security.application-groups": ["group.com.facebook.shared"],
                "keychain-access-groups": ["TEAM.com.facebook.keychain"],
                "aps-environment": "production",
            },
            with_ext=True,
        )
        rep = mod.inspect(ipa)
        self.assertEqual(rep["clone_preflight"]["status"], "warning")
        codes = {i["code"] for i in rep["issues"]}
        self.assertIn("ENTITLEMENT_APP_GROUPS", codes)
        self.assertIn("ENTITLEMENT_KEYCHAIN", codes)
        self.assertIn("ENTITLEMENT_PUSH", codes)
        self.assertIn("EMBEDDED_EXTENSIONS", codes)
        self.assertIn("THIRD_PARTY_SERVER_VERIFICATION", codes)

    def test_unsupported_x86_64_architecture_blocked(self):
        ipa = create_test_ipa(
            Path(self.tmp.name) / "sim.ipa",
            bundle_id="com.example.simonly",
            cputype=0x01000007,  # x86_64 simulator binary
        )
        rep = mod.inspect(ipa)
        self.assertEqual(rep["clone_preflight"]["status"], "incompatible")
        codes = {i["code"] for i in rep["issues"]}
        self.assertIn("UNSUPPORTED_ARCH", codes)


if __name__ == "__main__":
    unittest.main()
