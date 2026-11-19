#!/usr/bin/env python3
"""Build and validate deterministic changed-file bundles from content manifests.

A bundle is a ZIP_STORED archive of only added/modified files. Removals are
represented by the difference between the old and new manifests, not ZIP entries.
This is a release-building tool, not an installer or a transport protocol.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import zipfile

from content_manifest import ManifestError, load_manifest, validate_path

CHUNK_SIZE = 1024 * 1024
FIXED_DATE = (1980, 1, 1, 0, 0, 0)


def _plan(old, new):
    previous = {entry["path"]: entry for entry in old["files"]}
    current = {entry["path"]: entry for entry in new["files"]}
    changed = sorted(path for path in current if previous.get(path) != current[path])
    removed = sorted(previous.keys() - current.keys())
    return changed, removed, current


def _source_file(root, relative):
    validate_path(relative)
    if root.is_symlink() or not root.is_dir():
        raise ManifestError(f"Content root must be a real directory: {root}")
    entry = root
    for component in relative.split("/"):
        entry = entry / component
        if entry.is_symlink():
            raise ManifestError(f"Bundle source cannot be a symlink: {relative}")
    return entry


def _zip_info(name):
    info = zipfile.ZipInfo(name, FIXED_DATE)
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    return info


def _copy_verified(root, entry, target):
    relative = entry["path"]
    source = _source_file(root, relative)
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(source, flags)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            raise ManifestError(f"Bundle source is not a regular file: {relative}")
        sha = hashlib.sha256()
        size = 0
        with os.fdopen(os.dup(fd), "rb") as stream:
            while True:
                chunk = stream.read(CHUNK_SIZE)
                if not chunk:
                    break
                target.write(chunk)
                sha.update(chunk)
                size += len(chunk)
        after = os.fstat(fd)
        if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
                after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            raise ManifestError(f"Bundle source changed during read: {relative}")
        if size != entry["bytes"] or sha.hexdigest() != entry["sha256"]:
            raise ManifestError(f"Bundle source does not match new manifest: {relative}")
    finally:
        os.close(fd)


def pack(old_manifest, new_manifest, content_root, output):
    old = load_manifest(old_manifest)
    new = load_manifest(new_manifest)
    changed, removed, indexed = _plan(old, new)
    content_root = Path(content_root)
    output = Path(output)
    if content_root.is_symlink() or not content_root.is_dir():
        raise ManifestError("Content root must be a real directory")
    if output.is_symlink():
        raise ManifestError("Bundle output must not be a symlink")
    if output.resolve().is_relative_to(content_root.resolve()):
        raise ManifestError("Bundle output must not be inside the content root")
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=".content-delta-", suffix=".tmp", dir=output.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(temp_name, mode="w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
            for name in changed:
                with archive.open(_zip_info(name), mode="w", force_zip64=True) as target:
                    _copy_verified(content_root, indexed[name], target)
        os.replace(temp_name, output)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)
    return {"files": len(changed), "bytes": sum(indexed[name]["bytes"] for name in changed),
            "removed": removed, "archive": str(output)}


def verify(old_manifest, new_manifest, bundle):
    old = load_manifest(old_manifest)
    new = load_manifest(new_manifest)
    changed, removed, indexed = _plan(old, new)
    bundle = Path(bundle)
    if bundle.is_symlink():
        raise ManifestError("Bundle archive must not be a symlink")
    with zipfile.ZipFile(bundle, "r") as archive:
        infos = archive.infolist()
        if [info.filename for info in infos] != changed:
            raise ManifestError("Bundle entries differ from added/modified manifest files")
        for info in infos:
            validate_path(info.filename)
            expected = indexed[info.filename]
            file_type = (info.external_attr >> 16) & 0o170000
            if (info.is_dir() or info.compress_type != zipfile.ZIP_STORED
                    or (file_type not in (0, stat.S_IFREG))
                    or info.file_size != expected["bytes"]
                    or info.compress_size != expected["bytes"]):
                raise ManifestError(f"Unsafe or mismatched bundle entry: {info.filename}")
            digest = hashlib.sha256()
            count = 0
            with archive.open(info, "r") as stream:
                while True:
                    chunk = stream.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    digest.update(chunk)
                    count += len(chunk)
            if count != expected["bytes"] or digest.hexdigest() != expected["sha256"]:
                raise ManifestError(f"Bundle checksum mismatch: {info.filename}")
    return {"ok": True, "files": len(changed), "bytes": sum(indexed[name]["bytes"] for name in changed),
            "removed": removed}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("pack", help="Build changed-file ZIP from two manifests")
    create.add_argument("old_manifest", type=Path)
    create.add_argument("new_manifest", type=Path)
    create.add_argument("content_root", type=Path)
    create.add_argument("output", type=Path)
    check = commands.add_parser("verify", help="Verify a ZIP against both manifests")
    check.add_argument("old_manifest", type=Path)
    check.add_argument("new_manifest", type=Path)
    check.add_argument("bundle", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "pack":
            result = pack(args.old_manifest, args.new_manifest, args.content_root, args.output)
        else:
            result = verify(args.old_manifest, args.new_manifest, args.bundle)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except (ManifestError, OSError, ValueError, UnicodeError, zipfile.BadZipFile, RuntimeError) as exc:
        print(f"content_delta_bundle: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
