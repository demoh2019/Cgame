# Upstream backport review: FBX neutral bones and CPU affinity

Target: `demoh2019/Cgame` / `develop`. Date: 2026-11-19.

## Selected

1. [godotengine/godot#125230](https://github.com/godotengine/godot/pull/125230) — Linux
   `sched_getaffinity()`-aware default worker pool sizing. The patch also
   propagates the default thread count to NavigationServer2D/3D, Basis Universal,
   raycast occlusion and RenderingDevice transfer workers, with documentation.
   This avoids oversubscribing CPUs when running inside restricted affinity masks.
2. [godotengine/godot#125492](https://github.com/godotengine/godot/pull/125492) —
   preserve unweighted FBX vertices by assigning them to a neutral skeleton bone.
   One neutral bone is reused per skeleton, its inverse bind is calculated in
   skeleton space, and skins are validated before skeleton construction.

Both upstream PRs were **open when reviewed**. Their patches should be rechecked
before future upstream syncs; they are not guaranteed to have upstream approval.

## Already in Cgame/develop; intentionally skipped

Inspected upstream PRs #125500, #125502, #125544, #125577,
#125595, #125602, #125619, #125620, #125621, plus the previously ported
#125593, #125582, and #125324. For the inspected hunks, existing `develop`
source matched upstream changes or was already adapted; reapplying them would
cause conflicts or duplicate work. Partial adaptations such as #125604 and
#125615 were not overwritten.

## Tests

- Two native C++ `[OS]` test cases in `tests/core/os/test_os.cpp`:
  positive default thread count across platforms, and Linux default worker pool
  size equal to the process CPU affinity mask (if reading the mask succeeds).
- 22 Python **source-contract** regression tests in
  `misc/scripts/tests/test_upstream_fbx_affinity_20261119.py`.
  These cover per-module worker count usage and FBX skeleton skinning invariants.
- Python 3.10/3.13 CI workflow in
  `.github/workflows/upstream-fbx-affinity-regression.yml`.

Run source guards locally:

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_fbx_affinity_20261119.py -v
```

For native testing, build Godot with `tests=yes` on Linux and run the
`[OS]` doctest cases. For FBX, validate imports of a partially skinned
mesh with zero-weight vertices plus an animated armature, checking the
positions of vertices not influenced by bones in the imported scene.

**Limitations:** Source-contract tests are not runtime tests. No full C++
build, native FBX import fixture, or platform CI was available in the
authoring environment. The upstream FBX logic should undergo importer
smoke tests before a tagged release.
