# Cgame glTF import/export upstream review (2026-11-19)

Target: `demoh2019/Cgame:develop` — selected upstream patches reviewed
as source-specific backports, not a wholesale sync. Both PRs remained open
upstream at review time.

## Added

- [Godot #123240](https://github.com/godotengine/godot/pull/123240):
  fix `GLTFAccessor::decode_as_variants` for `PackedByteArray`,
  `PackedInt32Array`, `PackedInt64Array`, `PackedFloat32Array` and
  `PackedFloat64Array`. Previously each row wrote at the outer accessor index
  instead of the packed array's local component index, and omitted assigning
  the decoded array into the result. The backport fixes both.
- [Godot #120391](https://github.com/godotengine/godot/pull/120391):
  correct glTF spotlight cone / attenuation conversion; handle exactly equal
  inner and outer cone angles safely, and normalize degree-radian conversion
  in imported/exported property expressions.

These changes improve importing assets from Blender, Unity-converted glTF
and other external 3D pipelines.

## Tests

- Three **native C++** `[SceneTree][GLTFDocument]` regression cases added to
  `tests/scene/test_gltf_document.cpp`:
  five packed numeric Variant types across two accessor entries; spotlight
  attenuation roundtrip; equal inner/outer cone safety.
- Twelve **source-contract** regression tests added to
  `misc/scripts/tests/test_upstream_gltf_backports_20261119.py`.
- CI workflow runs Python 3.10 and 3.13 source-contract tests.

Run source tests:
```sh
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_gltf_backports_20261119.py -v
```
After building Godot with tests=yes, run native `[GLTFDocument]` tests and
an actual glTF import/export smoke test.

## Safety and limitations

Source-contract tests are not a compiled engine or runtime verification. No
local C++ compile or graphics-driver tests were performed while preparing
this review. Future upstream commits may change the still-open PRs; review
again when synchronizing.
