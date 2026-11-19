# Cgame OBJ and ImporterMesh upstream review — 2026-11-19

Target: `demoh2019/Cgame:develop`. This is a targeted backport of
upstream still-open Godot PRs. Exact source hunks were matched before edit.

## Selected upstream patches

- [#119021](https://github.com/godotengine/godot/pull/119021):
  provide **opt-in** OBJ MTL `Kd` linear-to-sRGB conversion via
  `materials/mtl_diffuse_is_linear` (default: false).
  This preserves preexisting OBJ appearance and avoids assuming an MTL RGB
  transfer function; the upstream patch's unconditional conversion was
  replaced after reviewing maintainer feedback. Other MTL parameters are
  unchanged.
- [#124098](https://github.com/godotengine/godot/pull/124098):
  batch ArrayMesh `changed` signals during `ImporterMesh::get_mesh()` so
  scene consumers never react to an incomplete mesh with only some surfaces.
  ImporterMesh has friend access to Resource's emit-change guard.

These are useful for 3D asset portability from Unreal/Unity/Blender and for
retaining material overrides when reimporting meshes.

## Regression tests

- Native C++ `[SceneTree][ImporterMesh]` test for 1, 2 and 4 surfaces:
  an ArrayMesh supplied as the base receives exactly one `changed` signal,
  after the full surface count is available.
- Native C++ `[SceneTree][OBJ]` editor test imports a small OBJ/MTL fixture
  with `Kd 0.5 0.25 1.0`, and checks absent, explicitly disabled and
  enabled linear conversion options (legacy vs sRGB albedo).
- 17 Python source-contract regression tests in
  `misc/scripts/tests/test_upstream_obj_mesh_20261119.py`, run by
  `.github/workflows/upstream-obj-mesh-regressions.yml` on Python 3.10 and 3.13.

Local source contract command:
```sh
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_obj_mesh_20261119.py -v
```

Please run the engine's compiled native `[ImporterMesh]` and `[OBJ]`
test cases, reimport a user-edited ArrayMesh and compare overrides, and verify
material colors visually in the editor before a release. No Godot executable,
native compile, or graphical smoke test was available here. Source checks are
not a substitute for native tests.

## Exclusions

Upstream #121025 (multithreaded resource load token leak) was reviewed but
**not** ported. A reviewer noted a possible new deadlock involving the
LoadToken destructor and the resource-load mutex on 2026-11-18. Wait for
upstream race resolution and a stress fixture before deciding to import it.

## Compatibility correction

Review of the upstream #119021 discussion found no MTL-defined encoding for
`Kd` and explicit maintainer concerns about changing the color of existing
projects. Cgame therefore keeps legacy sRGB-encoded interpretation by
default. For OBJ-as-Mesh imports from exporters that write linear Kd, opt
into **Materials → MTL Diffuse Is Linear** in import options, then reimport.
The scene import path also honors the same option when supplied through its
option map; editor scene import UI does not yet expose a dedicated control.
