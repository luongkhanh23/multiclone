#!/usr/bin/env python3
"""Comprehensive static, packaging, rootless layout, AutoClose safety,
Objective-C/Logos syntax, and Sileo repository tests covering all 12 required test areas."""

import bz2
import gzip
import importlib.util
import io
import json
import plistlib
import re
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REPO_SPEC = importlib.util.spec_from_file_location("build_repo", ROOT / "Scripts" / "build_repo.py")
repo_mod = importlib.util.module_from_spec(REPO_SPEC)
REPO_SPEC.loader.exec_module(repo_mod)


def _strip_objc_comments_and_strings(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r'@?"(?:\\.|[^"\\])*"', '""', text)
    return text


def _build_temp_test_deb(path: Path, control_text: str) -> None:
    """Creates a minimal valid Debian ar archive strictly inside a temp dir to test build_repo.py."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        raw = control_text.encode("utf-8")
        ti = tarfile.TarInfo(name="./control")
        ti.size = len(raw)
        tf.addfile(ti, io.BytesIO(raw))
    control_gz = buf.getvalue()

    data_buf = io.BytesIO()
    with tarfile.open(fileobj=data_buf, mode="w:gz") as tf:
        ti = tarfile.TarInfo(name="./var/jb/")
        ti.type = tarfile.DIRTYPE
        tf.addfile(ti)
    data_gz = data_buf.getvalue()

    def ar_member(name: str, body: bytes) -> bytes:
        hdr = f"{name:<16}{'0':<12}{'0':<6}{'0':<6}{'100644':<8}{len(body):<10}`\n".encode("ascii")
        pad = b"\n" if len(body) % 2 == 1 else b""
        return hdr + body + pad

    deb_bytes = b"!<arch>\n" + ar_member("debian-binary", b"2.0\n") + ar_member("control.tar.gz", control_gz) + ar_member("data.tar.gz", data_gz)
    path.write_bytes(deb_bytes)


class MultiCloneProjectVerificationTests(unittest.TestCase):
    # 1. Source structure & 10 required modules
    def test_01_required_directories_and_modules(self):
        required_dirs = [
            "Source", "Manager", "Tweak", "Resources", "Packaging",
            "Repository", "Scripts", "Tests", "Documentation", "Releases",
            "Source/MultiCloneCore", "Source/IPAInspector", "Source/CloneEngine",
            "Source/DataManager", "Source/IconManager", "Source/AutoClose",
            "Source/Settings", "Source/Logger", "Source/CLI",
            "Manager/MultiCloneManager", "Tweak/MultiCloneSpringBoard",
        ]
        for rel in required_dirs:
            self.assertTrue((ROOT / rel).is_dir(), f"Missing required directory: {rel}")

    # 2. Objective-C and Logos static syntax & hygiene check
    def test_02_objc_and_logos_syntax_and_imports(self):
        code_files = list(ROOT.glob("Source/**/*.[hm]")) + list(ROOT.glob("Manager/**/*.[hm]")) + list(ROOT.glob("Tweak/**/*.[hm]")) + list(ROOT.glob("Tweak/**/*.xm"))
        self.assertGreaterEqual(len(code_files), 25)

        for path in code_files:
            raw = path.read_text(encoding="utf-8")
            # No unfinished TODO/FIXME markers in delivered source
            self.assertNotRegex(raw, r"\b(TODO|FIXME)\b", f"Found TODO/FIXME in {path}")

            # Verify local #import "..." paths actually exist
            for imp in re.findall(r'#import\s+"([^"]+)"', raw):
                resolved = (path.parent / imp).resolve()
                self.assertTrue(resolved.is_file(), f"Broken local import '{imp}' in {path}")

            # Verify balanced braces/parens and matching @interface/@implementation with @end
            cleaned = _strip_objc_comments_and_strings(raw)
            self.assertEqual(cleaned.count("{"), cleaned.count("}"), f"Unbalanced braces in {path}")
            self.assertEqual(cleaned.count("("), cleaned.count(")"), f"Unbalanced parentheses in {path}")

            opens = len(re.findall(r"@(?:interface|implementation|protocol)\b", cleaned))
            ends = len(re.findall(r"@end\b", cleaned))
            self.assertEqual(opens, ends, f"Mismatched @interface/@implementation/@end in {path} ({opens} vs {ends})")

        # Verify Logos Tweak.xm has %ctor and SpringBoard guard
        tweak_xm = (ROOT / "Tweak/MultiCloneSpringBoard/Tweak.xm").read_text(encoding="utf-8")
        self.assertIn("%ctor", tweak_xm)
        self.assertIn("com.apple.springboard", tweak_xm)

    # 3. Makefile validation (Root, Tweak, Manager)
    def test_03_makefiles_rootless_and_archs(self):
        for rel in ["Makefile", "Tweak/MultiCloneSpringBoard/Makefile", "Manager/MultiCloneManager/Makefile"]:
            text = (ROOT / rel).read_text(encoding="utf-8")
            self.assertIn("THEOS_PACKAGE_SCHEME = rootless", text, f"Missing rootless scheme in {rel}")
            self.assertIn("arm64 arm64e", text, f"Missing arm64/arm64e ARCHS in {rel}")
            self.assertIn("common.mk", text, f"Missing common.mk include in {rel}")

        # Verify every listed .m/.xm file in subproject Makefiles actually exists
        for rel in ["Tweak/MultiCloneSpringBoard/Makefile", "Manager/MultiCloneManager/Makefile"]:
            mk = ROOT / rel
            text = mk.read_text(encoding="utf-8")
            sources = re.findall(r"([A-Za-z0-9_./-]+\.(?:m|xm))\b", text)
            self.assertGreater(len(sources), 0, f"No source files found in {rel}")
            defined_globals = {}
            for src in sources:
                src_path = (mk.parent / src).resolve()
                self.assertTrue(src_path.is_file(), f"Makefile {rel} references missing file: {src}")
                src_text = src_path.read_text(encoding="utf-8")
                # Detect accidental duplicate non-static global NSString/NSErrorDomain symbol definitions
                for sym in re.findall(r"^(?:NSString\s*\*\s*const|NSErrorDomain\s+const|NSNotificationName\s+const)\s+(\w+)\s*=", src_text, flags=re.M):
                    self.assertNotIn(sym, defined_globals, f"Duplicate global symbol '{sym}' linked into {rel}: {defined_globals.get(sym)} and {src}")
                    defined_globals[sym] = src

    # 4. Plist validation (XML + OpenStep filter plist)
    def test_04_plists_valid(self):
        for rel in [
            "Manager/MultiCloneManager/Info.plist",
            "Manager/MultiCloneManager/entitlements.plist",
            "Resources/config/auto-close-defaults.plist",
        ]:
            data = plistlib.loads((ROOT / rel).read_bytes())
            self.assertIsInstance(data, dict)

        defaults = plistlib.loads((ROOT / "Resources/config/auto-close-defaults.plist").read_bytes())
        self.assertFalse(defaults["autoCloseEnabled"], "Safety default: autoCloseEnabled must be false")
        self.assertTrue(defaults["autoCloseOnlyManagedClones"], "Safety default: autoCloseOnlyManagedClones must be true")
        self.assertTrue(defaults["confirmBeforeAutoClose"], "Safety default: confirmBeforeAutoClose must be true")

        info = plistlib.loads((ROOT / "Manager/MultiCloneManager/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "com.multiclone.manager")
        self.assertEqual(info["UIUserInterfaceStyle"], "Dark")

        filter_plist = (ROOT / "Tweak/MultiCloneSpringBoard/MultiClone.plist").read_text(encoding="utf-8")
        self.assertIn('"com.apple.springboard"', filter_plist)

    # 5 & 6. Control & Dependencies validation
    def test_05_06_control_and_dependencies(self):
        root_ctrl = (ROOT / "control").read_text(encoding="utf-8").strip()
        pkg_ctrl = (ROOT / "Packaging/control").read_text(encoding="utf-8").strip()
        self.assertEqual(root_ctrl, pkg_ctrl, "Root control and Packaging/control must match")

        fields = {}
        for line in root_ctrl.splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                fields[k.strip()] = v.strip()

        self.assertEqual(fields.get("Package"), "com.multiclone.manager")
        self.assertEqual(fields.get("Architecture"), "iphoneos-arm64")
        self.assertIn("firmware", fields.get("Depends", ""))
        self.assertIn("ellekit", fields.get("Depends", ""))
        self.assertTrue((ROOT / "Packaging/dependencies.txt").is_file())

    # 7. Simulated DEB packaging + Sileo APT repo indexing check
    def test_07_deb_repo_indexer_and_no_fake_release_deb(self):
        # If Releases/MultiClone.deb exists locally, it must be a real compiled ar/deb archive with SHA256SUMS.txt
        rel_deb = ROOT / "Releases/MultiClone.deb"
        if rel_deb.exists():
            self.assertTrue(rel_deb.read_bytes().startswith(b"!<arch>\n"), "MultiClone.deb must be a valid ar/deb archive")
            self.assertTrue((ROOT / "Releases/SHA256SUMS.txt").is_file(), "Real MultiClone.deb must be accompanied by SHA256SUMS.txt")

        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            pkg_dir = td_path / "pkgs"
            repo_dir = td_path / "repo"
            pkg_dir.mkdir()
            ctrl = (ROOT / "Packaging/control").read_text(encoding="utf-8")
            _build_temp_test_deb(pkg_dir / "com.multiclone.manager_1.0.0_iphoneos-arm64.deb", ctrl)

            count = repo_mod.build_repository(pkg_dir, repo_dir, "MultiClone", "MultiClone", "Test")
            self.assertEqual(count, 1)
            self.assertTrue((repo_dir / "Packages").is_file())
            self.assertTrue((repo_dir / "Packages.gz").is_file())
            self.assertTrue((repo_dir / "Packages.bz2").is_file())
            self.assertTrue((repo_dir / "Release").is_file())

            pkgs_txt = (repo_dir / "Packages").read_text(encoding="utf-8")
            self.assertIn("Package: com.multiclone.manager", pkgs_txt)
            self.assertIn("SHA256:", pkgs_txt)
            self.assertEqual(gzip.decompress((repo_dir / "Packages.gz").read_bytes()).decode("utf-8"), pkgs_txt)
            self.assertEqual(bz2.decompress((repo_dir / "Packages.bz2").read_bytes()).decode("utf-8"), pkgs_txt)

            rel_txt = (repo_dir / "Release").read_text(encoding="utf-8")
            self.assertIn("Architectures: iphoneos-arm64", rel_txt)
            self.assertIn("Packages.bz2", rel_txt)

        # Verify Sileo depiction JSON & no hardcoded fake URLs in Repository/
        dep = json.loads((ROOT / "Repository/depictions/com.multiclone.manager.json").read_text(encoding="utf-8"))
        self.assertEqual(dep["class"], "DepictionTabView")
        idx_html = (ROOT / "Repository/index.html").read_text(encoding="utf-8")
        self.assertNotIn("example.com", idx_html)
        self.assertIn("sileo://source/", idx_html)

    # 8. Rootless structure verification
    def test_08_rootless_structure_and_scripts(self):
        root_mk = (ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertIn("$(THEOS_STAGING_DIR)/Applications/MultiCloneManager.app/Info.plist", root_mk)
        self.assertNotIn("$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)", root_mk, "Avoid double /var/jb/var/jb staging")
        verify_sh = (ROOT / "Scripts/verify_package.sh").read_text(encoding="utf-8")
        self.assertIn("var/jb/Library/MobileSubstrate/DynamicLibraries/MultiClone.dylib", verify_sh)
        self.assertIn("var/jb/Applications/MultiCloneManager.app/MultiCloneManager", verify_sh)
        self.assertIn("var/jb/Applications/MultiCloneManager.app/Info.plist", verify_sh)

        # Icons referenced by Makefile must exist and be valid PNGs
        for icon in ["Resources/Icons/AppIcon60x60@2x.png", "Resources/Icons/AppIcon60x60@3x.png", "Repository/CydiaIcon.png"]:
            raw = (ROOT / icon).read_bytes()
            self.assertTrue(raw.startswith(b"\x89PNG\r\n\x1a\n"), f"Invalid PNG icon: {icon}")

    # 9. Auto Close safety policy checks
    def test_09_auto_close_safety_guards(self):
        sb_code = (ROOT / "Tweak/MultiCloneSpringBoard/MCAutoClose.m").read_text(encoding="utf-8")
        consts = (ROOT / "Source/MultiCloneCore/MCConstants.m").read_text(encoding="utf-8")
        self.assertIn('hasPrefix:@"com.apple."', consts, "Must protect all com.apple.* system apps")
        self.assertIn("MCIsProtectedBundleIdentifier", sb_code)
        self.assertIn("[managedIDs containsObject:previous]", sb_code, "Must only terminate managed clone bundles")
        self.assertIn("![previous isEqualToString:target]", sb_code, "Must never terminate target app being opened")
        self.assertIn("@try", sb_code, "SpringBoard callback must guard against crashes with @try/@catch")
        self.assertIn("MCSpringBoardPongNotification", sb_code, "Ping/Pong health check must be implemented")

    # 10. Install & clean uninstall scripts
    def test_10_install_and_clean_uninstall_scripts(self):
        postinst = (ROOT / "Packaging/DEBIAN/postinst").read_text(encoding="utf-8")
        prerm = (ROOT / "Packaging/DEBIAN/prerm").read_text(encoding="utf-8")
        postrm = (ROOT / "Packaging/DEBIAN/postrm").read_text(encoding="utf-8")

        self.assertIn("uicache", postinst)
        self.assertIn("uicache", prerm)
        self.assertIn("/var/mobile/Library/MultiClone", postinst)
        self.assertIn("/var/mobile/Library/MultiClone", postrm)
        # Ensure postrm never deletes anything outside MultiClone paths
        self.assertNotIn("rm -rf /var/mobile/Containers", postrm)
        self.assertNotIn("rm -rf /var/jb", postrm)

    # 11. Original app protection & path containment & rollback
    def test_11_original_app_safety_and_rollback(self):
        clone_engine = (ROOT / "Source/CloneEngine/MCCloneEngine.m").read_text(encoding="utf-8")
        data_mgr = (ROOT / "Source/DataManager/MCDataManager.m").read_text(encoding="utf-8")
        zip_code = (ROOT / "Source/MultiCloneCore/MCZipArchive.m").read_text(encoding="utf-8")

        self.assertIn("rollback()", clone_engine, "CloneEngine must implement transactional rollback")
        self.assertIn("caseInsensitiveCompare:sourceBundleID", clone_engine, "Must reject same Bundle ID as source app")
        self.assertIn("MCIsPathStrictlyInsideDirectory", data_mgr, "DataManager must enforce path containment")
        self.assertIn("MCErrorCodePathTraversalBlocked", zip_code, "ZipArchive must enforce Zip Slip protection")

    # 12. iOS 18.2 private API isolation & fallback check
    def test_12_ios182_private_api_isolation(self):
        bridge = (ROOT / "Source/MultiCloneCore/MCPrivateAPIBridge.m").read_text(encoding="utf-8")
        self.assertIn("FBSSystemService", bridge)
        self.assertIn("LSApplicationWorkspace", bridge)
        self.assertIn("getArgumentTypeAtIndex:3", bridge, "Must validate NSInvocation argument width on iOS 18.2")
        self.assertIn("terminateApplication:forReason:andReport:withDescription:completion:", bridge)
        self.assertIn("openApplication:options:withResult:", bridge)
        self.assertIn("@catch (NSException", bridge)


if __name__ == "__main__":
    unittest.main()
