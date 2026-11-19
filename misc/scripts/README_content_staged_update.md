# Verified staged content updates (roadmap #61, Content Delivery)

The content_staged_update.py tool assembles a complete **new release directory** by combining unchanged files from the installed game with new and modified files from a validated incremental ZIP. It does not download content, modify the current installation, or activate the new version. Python 3.9+ and standard library only.

## Workflow

Build versioned manifests and an incremental package, then stage a new version:

    python3 misc/scripts/content_manifest.py build /releases/v1 --output /manifests/v1.json
    python3 misc/scripts/content_manifest.py build /releases/v2 --output /manifests/v2.json
    python3 misc/scripts/content_delta_bundle.py pack /manifests/v1.json /manifests/v2.json /releases/v2 /packages/v1-to-v2.zip
    python3 misc/scripts/content_staged_update.py /manifests/v1.json /manifests/v2.json /releases/v1 /packages/v1-to-v2.zip /releases/v2-staged
    python3 misc/scripts/content_manifest.py verify /releases/v2-staged /manifests/v2.json

The final directory must not exist and must lie outside the installed release. Its parent must exist and must not be a symlink. Success prints a JSON summary: total staged files, delta/reused/removed file counts, bytes and path. Invalid input or any copy failure exits nonzero and removes the temporary staging directory.

## Safety and limitations

- The installed tree is fully inventoried and checked against the old manifest before staging. Every unchanged file is rehashed while copying; each updated file arriving from the archive is also rehashed. A final full-tree scan must match the new manifest before staging is published with a directory rename.
- Paths follow manifest validation rules: no traversal, case-folding collisions, unsafe characters, or symlinks in installed content. ZIP types, file membership and hashes are verified without extracting arbitrary entries. Removed files are omitted from the new tree; no deletion instructions are executed.
- This is NOT a live-update installer. A deployment system must activate a completed directory separately, ensure exclusive access to the staging parent, manage disk space, and preserve rollback if required. Directory rename makes a completed staging directory visible on the same filesystem; it does not atomically replace an active version.
- Manifest format v1 does not preserve executable bits, timestamps or empty directories. New staged files are non-executable (0644). Native binaries that need executable permissions must be packaged through a trusted executable-aware pipeline.
- SHA-256 alone does not authenticate the publisher. The manifests and archives require signed or authenticated delivery before use in production. Use immutable source snapshots to prevent filesystem races.
- .git, .godot and other manifest-excluded build artifacts are not copied.

## Tests

    python3 -m unittest discover -s misc/scripts/tests -p test_content_staged_update.py -v

38 regression tests cover additions, modifications, removals, empty and binary files, nested Unicode paths, large files, validation failures, symlinks, tampered ZIPs, changed content during staging, cleanup after simulated failures, and CLI exit codes.
