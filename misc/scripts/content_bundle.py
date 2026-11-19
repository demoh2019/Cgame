#!/usr/bin/env python3
"""Reproducible, integrity-checked offline content packs for Godot projects."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import zipfile

import content_manifest as cm

MANIFEST_NAME = "manifest.json"
CONTENT_PREFIX = "content/"
MAX_TOTAL_BYTES = 4 * 1024 * 1024 * 1024
CHUNK = 1024 * 1024
FIXED_DATE = (1980, 1, 1, 0, 0, 0)


class BundleError(Exception):
    """A package is unsafe, incomplete, invalid, or inconsistent."""


def _zipinfo(name):
    info = zipfile.ZipInfo(name, FIXED_DATE)
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    return info


def _manifest_bytes(doc):
    return (json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _is_inside(child, root):
    try:
        child.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def _stream(source, target, expected):
    digest = hashlib.sha256()
    length = 0
    while True:
        block = source.read(min(CHUNK, expected["bytes"] - length + 1))
        if not block:
            break
        length += len(block)
        if length > expected["bytes"]:
            raise BundleError("Content exceeds declared size: " + expected["path"])
        digest.update(block)
        if target is not None:
            target.write(block)
    if length != expected["bytes"] or digest.hexdigest() != expected["sha256"]:
        raise BundleError("Content checksum or size mismatch: " + expected["path"])


def _entries(doc):
    total = sum(item["bytes"] for item in doc["files"])
    if total > MAX_TOTAL_BYTES:
        raise BundleError("Content pack exceeds 4 GiB unpacked limit")
    return doc["files"], total


def pack(root, manifest_path, output):
    root, manifest_path, output = map(Path, (root, manifest_path, output))
    if output.exists() or output.is_symlink():
        raise BundleError("Output bundle already exists")
    if _is_inside(output, root):
        raise BundleError("Output bundle must be outside the project tree")
    doc = cm.load_manifest(manifest_path)
    rows, total = _entries(doc)
    report = cm.verify(root, manifest_path)
    if not report["ok"]:
        raise BundleError("Project differs from manifest: " + json.dumps(report, sort_keys=True))
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".godot-bundle-", suffix=".zip", dir=output.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(temporary, "w", allowZip64=True) as archive:
            encoded_manifest = _manifest_bytes(doc)
            if len(encoded_manifest) > cm.MAX_MANIFEST_BYTES:
                raise BundleError("Serialized manifest exceeds the 16 MiB limit")
            archive.writestr(_zipinfo(MANIFEST_NAME), encoded_manifest)
            for row in rows:
                source_path = root / row["path"]
                if any(part.is_symlink() for part in (root, *list(source_path.parents)[:-1], source_path)):
                    raise BundleError("Symlink detected while packing: " + row["path"])
                flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
                fd = os.open(source_path, flags)
                with os.fdopen(fd, "rb") as source:
                    before = os.fstat(source.fileno())
                    if not stat.S_ISREG(before.st_mode):
                        raise BundleError("Not a regular file: " + row["path"])
                    with archive.open(_zipinfo(CONTENT_PREFIX + row["path"]), "w", force_zip64=True) as sink:
                        _stream(source, sink, row)
                    after = os.fstat(source.fileno())
                    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
                            after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
                        raise BundleError("Content changed while packing: " + row["path"])
        if output.exists() or output.is_symlink():
            raise BundleError("Output bundle appeared during packing")
        os.rename(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return {"files": len(rows), "bytes": total}


def _read_bundle(archive):
    infos = archive.infolist()
    if len(infos) > cm.MAX_FILES + 1:
        raise BundleError("Too many archive members")
    names = [info.filename for info in infos]
    if len(set(names)) != len(names) or names.count(MANIFEST_NAME) != 1:
        raise BundleError("Missing or duplicate archive members")
    for info in infos:
        mode = (info.external_attr >> 16) & 0xFFFF
        kind = stat.S_IFMT(mode)
        if (info.is_dir() or info.flag_bits & 1 or kind not in (0, stat.S_IFREG)
                or info.compress_type != zipfile.ZIP_STORED):
            raise BundleError("Unsupported archive member: " + info.filename)
    meta = archive.getinfo(MANIFEST_NAME)
    if meta.file_size > cm.MAX_MANIFEST_BYTES:
        raise BundleError("Oversized manifest")
    with archive.open(meta, "r") as source:
        raw = source.read(cm.MAX_MANIFEST_BYTES + 1)
    if len(raw) > cm.MAX_MANIFEST_BYTES:
        raise BundleError("Oversized manifest")
    with tempfile.TemporaryDirectory(prefix="godot-bundle-meta-") as directory:
        temporary = Path(directory) / "manifest.json"
        temporary.write_bytes(raw)
        doc = cm.load_manifest(temporary)
    rows, total = _entries(doc)
    expected = {MANIFEST_NAME} | {CONTENT_PREFIX + row["path"] for row in rows}
    if set(names) != expected:
        raise BundleError("Archive has missing or unexpected members")
    for row in rows:
        if archive.getinfo(CONTENT_PREFIX + row["path"]).file_size != row["bytes"]:
            raise BundleError("Archive member size mismatch: " + row["path"])
    return rows, total


def _check_or_extract(bundle, destination=None):
    stage = None
    try:
        if destination is not None:
            destination = Path(destination)
            if destination.exists() or destination.is_symlink():
                raise BundleError("Destination already exists")
            if not destination.parent.is_dir() or destination.parent.is_symlink():
                raise BundleError("Destination parent must be a real directory")
            stage = Path(tempfile.mkdtemp(prefix=".godot-bundle-stage-", dir=destination.parent))
        with zipfile.ZipFile(bundle, "r") as archive:
            rows, total = _read_bundle(archive)
            for row in rows:
                with archive.open(CONTENT_PREFIX + row["path"], "r") as source:
                    if stage is None:
                        _stream(source, None, row)
                    else:
                        target = stage / row["path"]
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with target.open("xb") as sink:
                            _stream(source, sink, row)
        if stage is not None:
            if destination.exists() or destination.is_symlink():
                raise BundleError("Destination appeared during extraction")
            os.rename(stage, destination)
            stage = None
        return {"files": len(rows), "bytes": total}
    finally:
        if stage is not None:
            shutil.rmtree(stage)


def verify(bundle):
    return _check_or_extract(bundle)


def extract(bundle, destination):
    return _check_or_extract(bundle, destination)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("pack", help="Build a deterministic offline content ZIP")
    build.add_argument("root", type=Path)
    build.add_argument("manifest", type=Path)
    build.add_argument("output", type=Path)
    check = commands.add_parser("verify", help="Check every file against the embedded manifest")
    check.add_argument("bundle", type=Path)
    unpack = commands.add_parser("extract", help="Verify and extract into a NEW destination")
    unpack.add_argument("bundle", type=Path)
    unpack.add_argument("destination", type=Path)
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "pack":
            result = pack(arguments.root, arguments.manifest, arguments.output)
        elif arguments.command == "verify":
            result = verify(arguments.bundle)
        else:
            result = extract(arguments.bundle, arguments.destination)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (BundleError, cm.ManifestError, OSError, zipfile.BadZipFile, ValueError,
            UnicodeError, EOFError, RuntimeError, json.JSONDecodeError) as error:
        print("content_bundle: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
