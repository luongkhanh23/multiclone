#!/usr/bin/env python3
"""Cross-platform Sileo APT Repository builder for MultiClone.

Reads real Debian .deb packages (ar archive -> control.tar.{gz,xz,zst,bz2}),
copies them into Repository/debs/, generates Packages, Packages.gz,
Packages.bz2, and Release (with real MD5Sum, SHA1, SHA256 hashes).
Works natively on Windows, Linux, and macOS without requiring dpkg-scanpackages.
"""

from __future__ import annotations

import argparse
import bz2
import datetime as dt
import gzip
import hashlib
import io
import lzma
import shutil
import tarfile
from pathlib import Path


def _read_deb_control(deb_path: Path) -> str:
    data = deb_path.read_bytes()
    if not data.startswith(b"!<arch>\n"):
        raise ValueError(f"Not a valid ar/deb archive: {deb_path}")

    pos = 8
    while pos + 60 <= len(data):
        header = data[pos : pos + 60]
        name = header[0:16].decode("ascii", errors="replace").strip().rstrip("/")
        size = int(header[48:58].decode("ascii").strip())
        body_start = pos + 60
        body_end = body_start + size
        member_data = data[body_start:body_end]
        pos = body_end + (size % 2)

        if name.startswith("control.tar"):
            if name.endswith(".gz"):
                raw_tar = gzip.decompress(member_data)
            elif name.endswith(".bz2"):
                raw_tar = bz2.decompress(member_data)
            elif name.endswith(".xz"):
                raw_tar = lzma.decompress(member_data)
            elif name == "control.tar":
                raw_tar = member_data
            else:
                raise ValueError(f"Unsupported control compression '{name}' in {deb_path}")

            with tarfile.open(fileobj=io.BytesIO(raw_tar), mode="r:") as tf:
                for member in tf.getmembers():
                    if member.name in ("control", "./control"):
                        f = tf.extractfile(member)
                        if f is not None:
                            return f.read().decode("utf-8").strip()
    raise ValueError(f"Missing DEBIAN/control inside {deb_path}")


def _hashes_for_bytes(blob: bytes) -> tuple[str, str, str]:
    return (
        hashlib.md5(blob).hexdigest(),
        hashlib.sha1(blob).hexdigest(),
        hashlib.sha256(blob).hexdigest(),
    )


def build_repository(pkg_dir: Path, repo_dir: Path, origin: str, label: str, description: str) -> int:
    repo_dir.mkdir(parents=True, exist_ok=True)
    debs_dir = repo_dir / "debs"
    debs_dir.mkdir(parents=True, exist_ok=True)

    deb_sources = sorted(p for p in pkg_dir.glob("*.deb") if p.is_file()) if pkg_dir.exists() else []
    stanzas: list[str] = []
    seen_keys: set[tuple[str, str, str]] = set()

    for src in deb_sources:
        control_text = _read_deb_control(src)
        fields = {}
        for ln in control_text.splitlines():
            if ":" in ln:
                k, v = ln.split(":", 1)
                fields[k.strip()] = v.strip()
        pkg_key = (fields.get("Package", src.name), fields.get("Version", ""), fields.get("Architecture", ""))
        if pkg_key in seen_keys:
            continue
        seen_keys.add(pkg_key)

        dest = debs_dir / src.name
        if src.resolve() != dest.resolve():
            shutil.copy2(src, dest)
        raw = dest.read_bytes()
        md5, sha1, sha256 = _hashes_for_bytes(raw)
        rel_filename = f"debs/{dest.name}"

        lines = [ln for ln in control_text.splitlines() if ln.strip()]
        lines.extend([
            f"Filename: {rel_filename}",
            f"Size: {len(raw)}",
            f"MD5sum: {md5}",
            f"SHA1: {sha1}",
            f"SHA256: {sha256}",
        ])
        stanzas.append("\n".join(lines))

    packages_text = ("\n\n".join(stanzas) + "\n") if stanzas else ""
    packages_bytes = packages_text.encode("utf-8")
    packages_gz_bytes = gzip.compress(packages_bytes, compresslevel=9)
    packages_bz2_bytes = bz2.compress(packages_bytes, compresslevel=9)

    (repo_dir / "Packages").write_bytes(packages_bytes)
    (repo_dir / "Packages.gz").write_bytes(packages_gz_bytes)
    (repo_dir / "Packages.bz2").write_bytes(packages_bz2_bytes)

    now_rfc = dt.datetime.now(dt.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    index_files = [
        ("Packages", packages_bytes),
        ("Packages.gz", packages_gz_bytes),
        ("Packages.bz2", packages_bz2_bytes),
    ]

    md5_lines, sha1_lines, sha256_lines = [], [], []
    for fname, content in index_files:
        m, s1, s256 = _hashes_for_bytes(content)
        md5_lines.append(f" {m} {len(content)} {fname}")
        sha1_lines.append(f" {s1} {len(content)} {fname}")
        sha256_lines.append(f" {s256} {len(content)} {fname}")

    release_text = "\n".join([
        f"Origin: {origin}",
        f"Label: {label}",
        "Suite: stable",
        "Version: 1.0",
        "Codename: iphoneos-arm64",
        "Architectures: iphoneos-arm64",
        "Components: main",
        f"Description: {description}",
        f"Date: {now_rfc}",
        "MD5Sum:",
        *md5_lines,
        "SHA1:",
        *sha1_lines,
        "SHA256:",
        *sha256_lines,
        "",
    ])
    (repo_dir / "Release").write_text(release_text, encoding="utf-8")
    (repo_dir / ".nojekyll").write_text("", encoding="utf-8")

    print(f"[MultiClone Repo] Indexed {len(stanzas)} package(s) into {repo_dir}")
    return len(stanzas)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Sileo APT repository metadata for MultiClone")
    parser.add_argument("pkg_dir", nargs="?", default="Releases", help="Directory containing built .deb files")
    parser.add_argument("repo_dir", nargs="?", default="Repository", help="Output Sileo repository directory")
    parser.add_argument("--origin", default="MultiClone Repository")
    parser.add_argument("--label", default="MultiClone")
    parser.add_argument("--description", default="Free Rootless iOS 18.2 / Dopamine Repository for MultiClone")
    args = parser.parse_args()

    build_repository(Path(args.pkg_dir), Path(args.repo_dir), args.origin, args.label, args.description)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
