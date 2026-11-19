# Offline content bundles (roadmap #61, Content Delivery milestone)

`content_bundle.py` packages an already verified Godot project tree into a **reproducible ZIP** and checks or stages its contents without depending on the game engine. It builds on the adjacent `content_manifest.py` format-v1 release inventory.

```sh
python3 misc/scripts/content_manifest.py build game/ -o game/release.json
python3 misc/scripts/content_bundle.py pack game/ game/release.json game-release.zip
python3 misc/scripts/content_bundle.py verify game-release.zip
python3 misc/scripts/content_bundle.py extract game-release.zip new-install/
python3 -m unittest discover -s misc/scripts/tests -p test_content_bundle.py -v
```

The package uses fixed ZIP timestamps, modes and sorted entries; it stores `manifest.json` and every file under `content/`. Packaging rejects changes since the manifest was generated, unsafe source symlinks, and bundles written inside the project tree. Output bundles must not already exist. Rebuilding identical content creates identical ZIP bytes across runs using the same Python ZIP implementation.

Verification and extraction **read the embedded manifest, validate every archive entry and rehash every byte**. Rejects missing/extra/duplicate files, unexpected compression, nonregular entries, invalid filenames, mismatched file sizes and SHA-256, oversized manifests and more than 4 GiB of unpacked content. Extraction writes to a unique temporary sibling directory first, cleans it on failure and promotes it only after every file validates. Destination must not already exist; existing game installations are never overwritten. Commands print JSON reports and exit `0` on success, `2` on invalid data or I/O errors.

## Trust limits

This is an **offline asset packer**, not an authenticated CDN, secure remote updater, cryptographic release signing system, or Godot runtime asset loader. An attacker able to replace both content and unsigned manifest can forge a valid-looking bundle: authenticate release metadata independently. Content must be packaged from an immutable trusted staging tree; hostile concurrent filesystem mutation remains outside this tool's threat model. Do not extract archives into live installations, and do not run scripts from untrusted packs. Platform-specific resource import and remapping are separate future work.
