#!/usr/bin/env python3
"""Build a verified, non-destructive next-release tree from a content delta ZIP.

The existing installation is never modified. This tool stages a complete release
in a new directory; a separate, authenticated deployment system must activate it.
"""

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

from content_manifest import ManifestError, inventory, load_manifest, validate_path
from content_delta_bundle import verify as verify_bundle

BLOCK_SIZE = 1024 * 1024


def _file_index(document):
    return {item["path"]: item for item in document["files"]}


def _checked_old_file(root, relative):
    """Reject symlink components and open an unchanged file without following leaf links."""
    validate_path(relative)
    cursor = root
    for component in relative.split("/"):
        cursor = cursor / component
        if cursor.is_symlink():
            raise ManifestError(f"Symlink in installed content path: {relative}")
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(cursor, flags)
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode):
        os.close(descriptor)
        raise ManifestError(f"Installed content is not a regular file: {relative}")
    return descriptor, before


def _copy_and_check(stream, destination, expected, before=None, descriptor=None):
    digest = hashlib.sha256()
    copied = 0
    with destination.open("xb") as target:
        while True:
            block = stream.read(BLOCK_SIZE)
            if not block:
                break
            target.write(block)
            digest.update(block)
            copied += len(block)
    if before is not None:
        after = os.fstat(descriptor)
        identity = lambda item: (item.st_dev, item.st_ino, item.st_size, item.st_mtime_ns)
        if identity(before) != identity(after):
            raise ManifestError(f"Installed content changed during copy: {expected['path']}")
    if copied != expected["bytes"] or digest.hexdigest() != expected["sha256"]:
        raise ManifestError(f"Copied file does not match manifest: {expected['path']}")


def _installed_inventory(root, old_manifest):
    """Manifests can be stored in the old project tree without self-hashing."""
    excluded = None
    try:
        excluded = old_manifest.absolute().relative_to(root.absolute()).as_posix()
    except ValueError:
        pass
    return inventory(root, excluded_manifest=excluded)["files"]


def stage(old_manifest, new_manifest, installed_root, delta_zip, output):
    """Return a complete, validated next-release directory at a previously absent path."""
    old_manifest = Path(old_manifest)
    new_manifest = Path(new_manifest)
    installed_root = Path(installed_root)
    delta_zip = Path(delta_zip)
    output = Path(output)

    if installed_root.is_symlink() or not installed_root.is_dir():
        raise ManifestError("Installed root must be a real directory")
    if output.exists() or output.is_symlink():
        raise ManifestError("Staging output already exists; refusing to overwrite")
    if output.parent.is_symlink() or not output.parent.is_dir():
        raise ManifestError("Staging output parent must be an existing, real directory")
    if output.resolve().is_relative_to(installed_root.resolve()):
        raise ManifestError("Staging output cannot be inside installed content")
    if delta_zip.is_symlink():
        raise ManifestError("Delta archive must not be a symlink")

    old = load_manifest(old_manifest)
    new = load_manifest(new_manifest)
    previous = _file_index(old)
    desired = _file_index(new)
    changed = sorted(name for name in desired if previous.get(name) != desired[name])
    reused = sorted(name for name in desired if previous.get(name) == desired[name])
    removed = sorted(previous.keys() - desired.keys())

    # Fail before writing anything if the installed version or received ZIP differs.
    if _installed_inventory(installed_root, old_manifest) != old["files"]:
        raise ManifestError("Installed content does not match the old manifest")
    verify_bundle(old_manifest, new_manifest, delta_zip)

    temporary = Path(tempfile.mkdtemp(prefix=".content-stage-", dir=output.parent))
    try:
        with zipfile.ZipFile(delta_zip, "r") as archive:
            for name in sorted(desired):
                entry = desired[name]
                destination = temporary.joinpath(*name.split("/"))
                destination.parent.mkdir(parents=True, exist_ok=True)
                if name in changed:
                    with archive.open(name, "r") as source:
                        _copy_and_check(source, destination, entry)
                else:
                    fd, before = _checked_old_file(installed_root, name)
                    try:
                        with os.fdopen(os.dup(fd), "rb") as source:
                            _copy_and_check(source, destination, entry, before, fd)
                    finally:
                        os.close(fd)
                destination.chmod(0o644)

        # Complete end-to-end validation also detects unforeseen extra files.
        if inventory(temporary)["files"] != new["files"]:
            raise ManifestError("Staged release does not match the new manifest")
        temporary.chmod(0o755)
        if output.exists() or output.is_symlink():
            raise ManifestError("Staging output was created concurrently")
        os.rename(temporary, output)
    except BaseException:
        shutil.rmtree(temporary)
        raise
    return {"staged_files": len(desired), "delta_files": len(changed),
            "reused_files": len(reused), "removed_files": len(removed),
            "staged_bytes": sum(entry["bytes"] for entry in desired.values()),
            "path": str(output)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("old_manifest", type=Path)
    parser.add_argument("new_manifest", type=Path)
    parser.add_argument("installed_root", type=Path)
    parser.add_argument("delta_zip", type=Path)
    parser.add_argument("output", type=Path, help="New, nonexistent directory outside the installed root")
    args = parser.parse_args(argv)
    try:
        result = stage(args.old_manifest, args.new_manifest, args.installed_root, args.delta_zip, args.output)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except (ManifestError, OSError, ValueError, UnicodeError, zipfile.BadZipFile, RuntimeError, KeyError) as error:
        print(f"content_staged_update: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
