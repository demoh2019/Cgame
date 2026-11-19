# Upstream editor/VR regression backports

This Cgame `develop` regression bundle covers two independent Godot
upstream pull requests. **#125557 was already on develop** when this
change was made; **#125473 is backported by this change**:

- [godotengine/godot#125557](https://github.com/godotengine/godot/pull/125557) —
  avoid filling OpenXR logs with identical frame-loop errors. A new failure
  code is logged once, repeated failures move to verbose logging, and a
  successful call resets each stage's error memory so a later failure is
  reported again. Wait, begin and end each have independent state, with both
  end-frame call paths sharing one state.
- [godotengine/godot#125473](https://github.com/godotengine/godot/pull/125473) —
  notify live GDScript owners when a hot-reloaded script's exported properties
  change in the editor. Instance IDs are captured under the language mutex;
  `ObjectDB` resolution and property-list notifications occur **outside** the
  mutex, guarding against deadlock and freed objects.

These changes are targeted regressions, **not** a general OpenXR runtime update
or an AI Game Builder feature. They do not add any external dependencies.

## Validation

Run the offline source-contract suite:

```sh
python3 -m unittest discover -s misc/scripts/tests -p 'test_upstream_editor_xr_regressions.py' -v
```

The dedicated `.github/workflows/upstream-editor-xr-backports.yml` workflow
runs Python 3.9 and Python 3.13 source contracts and builds the Linux Godot
editor with `tests=yes` and the OpenXR module enabled. It then runs headless
native tests and a basic GDScript project import check. Source-contract tests
verify the presence and structural order of protective branches; they do not
prove XR hardware recovery, hot-reload behavior inside the GUI, or performance.

## Manual tests still required

1. Open an `@tool` script attached to a live scene instance, alter an exported
   range/hint, save/reload, and check Inspector updates without reselecting.
2. On an OpenXR device, induce the same error in repeated `xrWaitFrame`,
   `xrBeginFrame` and `xrEndFrame` calls: expect one normal log per streak and
   subsequent verbose lines. After recovery, the next failure should report
   normally again.
3. Validate on Windows/macOS and XR runtimes in addition to Linux build CI.

These upstream PRs were still open when evaluated. Keep future upstream sync
checking for revised fixes before concluding that either PR is permanently
upstream-compatible.
