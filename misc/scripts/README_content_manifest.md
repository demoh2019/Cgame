# Content Delivery manifest (roadmap #61, item 43)

A **Python standard-library** CLI for preparing deterministic inventories of Godot project files and checking release integrity. This is an incremental Content Delivery foundation, **not** a live CDN, downloader, patch installer, cryptographic signing system, or in-engine asset streamer.

## Commands

```sh
python3 misc/scripts/content_manifest.py build /path/to/game --output /path/to/game/release.json
python3 misc/scripts/content_manifest.py verify /path/to/game /path/to/game/release.json
python3 misc/scripts/content_manifest.py diff /path/to/old.json /path/to/new.json
python3 -m unittest discover -s misc/scripts/tests -p test_content_manifest.py -v
```

`build` writes UTF-8, deterministic, key-sorted, indented format-v1 JSON atomically. Paths use forward slashes; entries are sorted, and all files are hashed via SHA-256 in chunks. Rebuilding an unchanged tree creates byte-identical JSON. The output file is omitted from inventory if located inside the project root.

Example v1 manifest:

```json
{
  "files": [
    {
      "bytes": 3,
      "path": "hello.txt",
      "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    }
  ],
  "format": 1
}
```

`verify` reports `ok`, `missing`, `extra`, and `modified`. `diff` reports `added`, `removed`, `modified`, `unchanged` and `download_bytes` (sum of complete new/changed files, *not* binary deltas). Both print machine-readable JSON.

Exit codes: `0` for success, `1` for valid manifests with content mismatches (`verify` only), `2` for invalid inputs, unsafe paths, filesystem errors, or malformed manifests.

## Portability and security

- `.git`, `.godot`, `.hg`, `.svn`, and `__pycache__` directories are ignored; `.DS_Store` and `Thumbs.db` files are ignored. Other hidden or ordinary files are included. This is a **file-level** manifest, not a `.pck` or engine resource dependency graph.
- Rejects symlinks, special files, case-insensitive file and parent-folder collisions, Unicode filenames not in NFC, traversal, backslashes, Windows reserved names, and non-portable paths. It does not follow symlinks outside a project.
- Reading each file uses a descriptor and detects size/mtime changes during hashing. Manifests have a 16 MiB size cap and a 100,000-entry cap. For untrusted distributions, run against an immutable snapshot and rely on authenticated channels plus signed release metadata: **a plain SHA-256 manifest alone does not prove publisher authenticity**.
- Format v1 intentionally preserves only relative paths, byte lengths and SHA-256; no host paths or timestamps. A future client can download into a separate staging directory, verify every file, and swap releases atomically only after full validation.

## Example release pipeline

1. Export or stage the final distributable project files into a clean directory.
2. Run `build`; publish the files and manifest together over authenticated transport.
3. Run `verify` on staged files in CI and before release.
4. Compare manifests with `diff` to estimate upload/download work.
5. When building a client updater, authenticate the manifest first, verify each downloaded file, preserve rollback metadata, and promote only validated staged releases.

**Limitations:** no remote download, binary delta algorithms, content-addressed cache, signed metadata, rollback implementation, Godot editor integration, or platform-specific packaging. Those are separate milestones, and roadmap #61 should remain open.