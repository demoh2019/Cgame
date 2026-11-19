#!/usr/bin/env python3
"""Build and verify deterministic, incremental ZIP packages from content manifests.

Requires the sibling content_manifest.py. Does not download, extract, or install files.
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

import content_manifest as manifest


class DeltaBundleError(Exception):
    """An unsafe bundle or content mismatch."""


def changed_entries(old, new):
    """Return sorted new/changed entries; removals are recorded by the manifests."""
    old_by_path = {item["path"]: item for item in old["files"]}
    return [entry for entry in new["files"] if old_by_path.get(entry["path"]) != entry]


def _secure_open(root, relative):
    """Reject links in all path components before opening the regular file."""
    manifest.validate_path(relative)
    if root.is_symlink() or not root.is_dir():
        raise DeltaBundleError("Project root must be a real directory")
    path = root
    for part in relative.split("/"):
        path = path / part
        if path.is_symlink():
            raise DeltaBundleError(f"Symlink in content path: {relative}")
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode):
        os.close(fd)
        raise DeltaBundleError(f"Not a regular file: {relative}")
    return fd, info


def build_bundle(old, new, root, output):
    entries = changed_entries(old, new)
    root = Path(root)
    output = Path(output)
    if root.is_symlink() or not root.is_dir():
        raise DeltaBundleError("Project root must be a real directory")
    destination = output.resolve(strict=False)
    for entry in entries:
        if (root / entry["path"]).resolve(strict=False) == destination:
            raise DeltaBundleError("Bundle output would replace a packaged content file")
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".content-delta-", suffix=".tmp", dir=output.parent)
    os.close(descriptor)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
            for entry in entries:
                path = entry["path"]
                fd, before = _secure_open(root, path)
                try:
                    digest = hashlib.sha256()
                    count = 0
                    # Fixed ZIP metadata makes builds reproducible across machines.
                    member = zipfile.ZipInfo(path, (1980, 1, 1, 0, 0, 0))
                    member.compress_type = zipfile.ZIP_STORED
                    member.create_system = 3
                    member.external_attr = 0o100644 << 16
                    with os.fdopen(os.dup(fd), "rb") as source, archive.open(member, "w") as target:
                        while True:
                            chunk = source.read(1024 * 1024)
                            if not chunk:
                                break
                            target.write(chunk)
                            digest.update(chunk)
                            count += len(chunk)
                    after = os.fstat(fd)
                    identity = lambda item: (item.st_dev, item.st_ino, item.st_size, item.st_mtime_ns)
                    if (identity(before) != identity(after) or count != entry["bytes"]
                            or digest.hexdigest() != entry["sha256"]):
                        raise DeltaBundleError(f"Content changed or mismatches manifest: {path}")
                finally:
                    os.close(fd)
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return {"packed": len(entries), "bytes": sum(item["bytes"] for item in entries)}


def verify_bundle(old, new, bundle):
    entries = changed_entries(old, new)
    expected = {entry["path"]: entry for entry in entries}
    with zipfile.ZipFile(bundle, "r") as archive:
        members = archive.infolist()
        if len(members) != len(expected):
            raise DeltaBundleError("Unexpected or missing ZIP members")
        actual_names = [member.filename for member in members]
        if actual_names != sorted(expected):
            raise DeltaBundleError("ZIP member names are not the expected sorted changed paths")
        for member in members:
            name = manifest.validate_path(member.filename)
            if (member.is_dir() or member.file_size != expected[name]["bytes"]
                    or member.compress_type != zipfile.ZIP_STORED):
                raise DeltaBundleError(f"Invalid ZIP member: {name}")
            mode = member.external_attr >> 16
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG):
                raise DeltaBundleError(f"Unsafe ZIP member type: {name}")
            digest = hashlib.sha256()
            with archive.open(member, "r") as stream:
                while True:
                    block = stream.read(1024 * 1024)
                    if not block:
                        break
                    digest.update(block)
            if digest.hexdigest() != expected[name]["sha256"]:
                raise DeltaBundleError(f"SHA-256 mismatch in bundle: {name}")
    return {"verified": len(entries)}


def main(argv=None):
    cli = argparse.ArgumentParser(description=__doc__)
    sub = cli.add_subparsers(dest="command", required=True)
    build = sub.add_parser("build", help="Create a ZIP containing only new or modified files")
    build.add_argument("old_manifest", type=Path)
    build.add_argument("new_manifest", type=Path)
    build.add_argument("root", type=Path)
    build.add_argument("--output", "-o", required=True, type=Path)
    verify = sub.add_parser("verify", help="Verify ZIP membership and SHA-256 without extracting")
    verify.add_argument("old_manifest", type=Path)
    verify.add_argument("new_manifest", type=Path)
    verify.add_argument("bundle", type=Path)
    args = cli.parse_args(argv)
    try:
        old = manifest.load_manifest(args.old_manifest)
        new = manifest.load_manifest(args.new_manifest)
        result = (build_bundle(old, new, args.root, args.output) if args.command == "build"
                  else verify_bundle(old, new, args.bundle))
        print(json.dumps(result, sort_keys=True))
        return 0
    except (manifest.ManifestError, DeltaBundleError, OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"content_delta_bundle: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
