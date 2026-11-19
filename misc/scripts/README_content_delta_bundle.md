# Reproducible changed-file bundles for Content Delivery

This is the next increment of [roadmap #61, item 43](https://github.com/demoh2019/Cgame/issues/61), building on `content_manifest.py`. It makes a deterministic ZIP containing **only files added or modified** between two verified, format-v1 content manifests. Removed files are inferred from the two manifests, not bundled as deletion instructions.

```sh
python3 misc/scripts/content_manifest.py build /path/to/old-content -o /tmp/old.json
python3 misc/scripts/content_manifest.py build /path/to/new-content -o /tmp/new.json
python3 misc/scripts/content_delta_bundle.py pack /tmp/old.json /tmp/new.json /path/to/new-content /tmp/delta.zip
python3 misc/scripts/content_delta_bundle.py verify /tmp/old.json /tmp/new.json /tmp/delta.zip
python3 -m unittest discover -s misc/scripts/tests -p 'test_content_delta_bundle.py' -v
```

The `pack` command validates both manifests, reads only added/modified files from the new content directory, checks every copied byte against its manifest SHA-256 and byte size, and atomically replaces the output ZIP only after successful completion. Place the output **outside** the source content directory. It refuses symlink sources, symlink output, modified files, malformed manifests and unsafe paths.

`verify` checks the ZIP entry list *exactly* against changed paths in sorted order, rejects non-regular entries, symbolic links and compression methods other than `ZIP_STORED`, and hashes all archive bytes without extraction. Both commands output JSON on success and exit with code `2` on invalid or mismatched input. ZIP entry order, UTC-independent timestamps (1980-01-01), mode bits and stored compression are fixed for reproducibility. ZIP64 support allows large assets.

**Limits and trust model:** This is a release assembly/verification tool only, not a binary-delta codec, CDN, installer, updater, downloader, signed manifest, authenticated transport, or automatic rollback manager. Always authenticate both manifests and the archive before distributing or installing content. A future staged updater must verify the complete installed release, handle deletions explicitly, and support rollback; never extract ZIP entries directly into a live game directory without such controls. The tool rejects symlinks in referenced source paths but cannot guarantee protection against a malicious process concurrently replacing parent directories: build releases from an immutable, trusted staging tree.
