# Cgame upstream backports — renderer memory and editor teardown (2026-11-19)

**Repository:** `demoh2019/Cgame`, branch `develop`.
**Upstream:** `godotengine/godot` pull requests. These are **selected** backports, not a wholesale merge of all PRs.

## Implemented

| Upstream PR | Cgame commits | Change |
| --- | --- | --- |
| [#125497](https://github.com/godotengine/godot/pull/125497) | `534afe1b1e6ca75a77720f2aea61c04699def10f`, `d736465ab3af3025fde30f5fa6fddac0df98b53e` | Replace unaligned `LocalVector<uint32_t>` validity masks with a raw pointer into the same 64-byte-aligned ray-packet buffer, so Embree AVX-512 aligned loads do not crash. Update allocation, clearing and raycast call sites. |
| [#125553](https://github.com/godotengine/godot/pull/125553) | `818c4c7ae6649ecdb5a2bb462a4b667807f3b8c3`, `7c701d506f92d75eeac10d951c86f99023c86a5e` | Zero reused shader-instance uniform slots and mark them dirty when allocated in GLES3 and RenderingDevice backends. |
| [#125566](https://github.com/godotengine/godot/pull/125566) | `4e03720061c6a8d95189134c6c97f3a207863dd5`, `25b7a60e27628fdc321340d7085a359fbbd97238`, `ebb77c555144d598a3ca69329f27b486b9b1868a`, `c87332e1a145f04d97cb6c9a8a860e518550db10` | Latch shutdown before releasing editor documentation; decline queued doc work after teardown; avoid accessing missing `EditorNode` and clear `EditorFileSystem` singleton in destructor. |

All three upstream PRs were **open** when selected. If upstream review changes their semantics, the fork must be reconciled before release.

## Added test coverage

- `misc/scripts/tests/test_upstream_renderer_memory_safety.py`: **18 source-level Python test methods** covering mask/ray alignment, memory lifetime, caller pointer type, renderer slot zeroing and dirty notification, and a mathematical sweep of alignment offsets and allocation sizes.
- `misc/scripts/tests/test_upstream_editor_shutdown.py`: **12 source-level Python test methods** covering startup/teardown safety and ordering of the documentation guard and singleton cleanup.
- `.github/workflows/upstream-renderer-memory-safety.yml`: runs source tests with Python 3.10/3.13 and builds the native Cgame editor with `tests=yes`.
- `.github/workflows/upstream-gdscript-editor-prs.yml`: runs additional editor-shutdown regression suite, compiles the native editor and repeats the headless editor startup/shutdown sequence three times.

Source contracts protect against accidentally reverting a safety fix. They are **not** evidence that the engine compiles or that Embree AVX-512 and GPU behavior were exercised.

During this session the committed source was independently reread and checked: **19/19 renderer constraints** and **12/12 editor-teardown constraints** passed. This does **not** mean all Python tests or the native C++ build completed: track GitHub Actions for their actual results.

## Reproduce checks

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_renderer_memory_safety.py -v
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_editor_shutdown.py -v
```

Native editor builds and real integration tests must also pass before the backports can be called production-ready. For Embree, test an AVX-512-enabled machine with raycast occlusion enabled and multiple viewport sizes; also compare GPU shader uniforms before/after slot reuse in both GLES3 and RenderingDevice renderers.
