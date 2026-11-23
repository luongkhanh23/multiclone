#!/usr/bin/env python3
"""Unit tests for MultiClone manifest manager (upgraded from v0.3)."""

import argparse
import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("mc_manifest", ROOT / "Source" / "CLI" / "mc_manifest.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        mod.MANIFEST = Path(self.tmp.name) / "instances.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_bundle_id_validation(self):
        self.assertTrue(mod.valid_bundle_id("com.example.app"))
        self.assertTrue(mod.valid_bundle_id("com.example.app.multiclone.001"))
        self.assertFalse(mod.valid_bundle_id("not-valid"))
        self.assertFalse(mod.valid_bundle_id("com..invalid"))
        self.assertFalse(mod.valid_bundle_id(".leading.dot"))

    def test_protected_bundles_blocked(self):
        self.assertTrue(mod.is_protected_bundle_id("com.apple.springboard"))
        self.assertTrue(mod.is_protected_bundle_id("com.apple.Preferences"))
        self.assertTrue(mod.is_protected_bundle_id("com.multiclone.manager"))
        self.assertTrue(mod.is_protected_bundle_id("org.coolstar.SileoStore"))
        self.assertFalse(mod.is_protected_bundle_id("com.example.myapp"))

        with self.assertRaises(SystemExit):
            mod.add(argparse.Namespace(bundle_id="com.apple.springboard", name="Illegal", ipa=None))

    def test_unique_planned_ids_and_rename_remove(self):
        with contextlib.redirect_stdout(io.StringIO()):
            mod.add(argparse.Namespace(bundle_id="com.example.app", name="First", ipa=None))
            mod.add(argparse.Namespace(bundle_id="com.example.app", name="Second", ipa=None))
            mod.add(argparse.Namespace(bundle_id="com.example.app", name="Third", ipa=None))

        records = json.loads(mod.MANIFEST.read_text(encoding="utf-8"))["instances"]
        self.assertEqual(len(records), 3)
        self.assertEqual(records[0]["planned_bundle_id"], "com.example.app.multiclone.001")
        self.assertEqual(records[1]["planned_bundle_id"], "com.example.app.multiclone.002")
        self.assertEqual(records[2]["planned_bundle_id"], "com.example.app.multiclone.003")

        with contextlib.redirect_stdout(io.StringIO()):
            mod.rename(argparse.Namespace(instance_id=records[0]["id"], name="Renamed First"))
            mod.remove(argparse.Namespace(instance_id=records[1]["id"]))

        after = json.loads(mod.MANIFEST.read_text(encoding="utf-8"))["instances"]
        self.assertEqual(len(after), 2)
        self.assertEqual(after[0]["display_name"], "Renamed First")


if __name__ == "__main__":
    unittest.main()
