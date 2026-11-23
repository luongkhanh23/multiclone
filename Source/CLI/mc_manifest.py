#!/usr/bin/env python3
"""Manage MultiClone instance manifests (backward-compatible with v0.3)."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "Resources" / "manifests" / "instances.json"

PROTECTED_EXACT = {
    "com.multiclone.manager",
    "com.opa334.dopamine",
    "org.coolstar.sileostore",
    "xyz.willy.zebra",
    "com.opa334.trollstore",
}


def load() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text(encoding="utf-8"))
    return {"schema": 2, "product": "MultiClone", "version": "1.0.0", "instances": []}


def save(data: dict) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    tmp = MANIFEST.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(MANIFEST)


def valid_bundle_id(value: str) -> bool:
    if not isinstance(value, str) or not (3 <= len(value) <= 180):
        return False
    return bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+", value))


def is_protected_bundle_id(value: str) -> bool:
    if not isinstance(value, str) or not value:
        return True
    low = value.lower()
    return low.startswith("com.apple.") or low in PROTECTED_EXACT


def add(args: argparse.Namespace) -> None:
    if not valid_bundle_id(args.bundle_id):
        raise SystemExit("Invalid bundle ID; expected reverse-DNS form, e.g. com.example.app")
    if is_protected_bundle_id(args.bundle_id):
        raise SystemExit("Refused: protected system or jailbreak bundle ID")

    data = load()
    used = {x.get("planned_bundle_id") for x in data["instances"]}
    n = 1
    while f"{args.bundle_id}.multiclone.{n:03d}" in used:
        n += 1

    now = dt.datetime.now(dt.timezone.utc).isoformat()
    record = {
        "id": str(uuid.uuid4()),
        "source_bundle_id": args.bundle_id,
        "planned_bundle_id": f"{args.bundle_id}.multiclone.{n:03d}",
        "display_name": args.name or f"Clone {n}",
        "source_ipa": str(Path(args.ipa).expanduser().resolve()) if args.ipa else "",
        "status": "configured",
        "created_at": now,
        "updated_at": now,
    }
    data["instances"].append(record)
    save(data)
    print(json.dumps(record, ensure_ascii=False, indent=2))


def rename(args: argparse.Namespace) -> None:
    data = load()
    for item in data["instances"]:
        if item.get("id") == args.instance_id:
            item["display_name"] = args.name
            item["updated_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
            save(data)
            print(json.dumps(item, ensure_ascii=False, indent=2))
            return
    raise SystemExit("Instance UUID not found")


def remove(args: argparse.Namespace) -> None:
    data = load()
    before = len(data["instances"])
    data["instances"] = [x for x in data["instances"] if x.get("id") != args.instance_id]
    if len(data["instances"]) == before:
        raise SystemExit("Instance UUID not found")
    save(data)
    print("Removed clone record", args.instance_id)


def main() -> None:
    p = argparse.ArgumentParser(description="MultiClone manifest manager")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("add")
    a.add_argument("bundle_id")
    a.add_argument("--name")
    a.add_argument("--ipa")
    a.set_defaults(func=add)

    rn = sub.add_parser("rename")
    rn.add_argument("instance_id")
    rn.add_argument("name")
    rn.set_defaults(func=rename)

    ls = sub.add_parser("list")
    ls.set_defaults(func=lambda _: print(json.dumps(load(), ensure_ascii=False, indent=2)))

    rm = sub.add_parser("remove")
    rm.add_argument("instance_id")
    rm.set_defaults(func=remove)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
