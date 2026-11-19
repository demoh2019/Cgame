# Upstream OpenXR fixes: property chaining and cleanup

This change ports the guard from [godotengine/godot#125556](https://github.com/godotengine/godot/pull/125556)
into Cgame, and adds regression tests for the **already integrated**
[godotengine/godot#125615](https://github.com/godotengine/godot/pull/125615).

## Runtime fixes

- **#125556 — Meta foveation property guard:** Only pass
  `meta_foveation_eye_tracked_properties` to the Vulkan runtime when the
  corresponding extension has actually been enabled. Some OpenXR runtimes
  reject an unsupported extension-specific `next` structure.
- **#125615 — cleanup** (existing in `develop`): Spatial container destruction
  releases handles and owner RIDs even if XR calls fail or the singleton is
  unavailable; self-render cleanup clears view/layer state regardless.
  This PR locks these fixes down with focused tests, without rewriting them.

## Verification

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_openxr_spatial_container_teardown.py -v
```

23 targeted tests inspect the production C++ source for error-handling and
frame-state reset invariants as well as the extension guard.
The six Python CI configurations run these checks on Linux, Windows and
macOS (3 operating systems × 2 Python versions).

These are **source-level regression contracts**, not a native engine build or
headset test. Confirm successful Vulkan/OpenXR startup on the affected
runtimes before treating real hardware behavior as fully validated.