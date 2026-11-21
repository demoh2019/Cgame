# Cgame Navigation (native)

Optional built-in 3D module that replaces the duplicated GDScript navigation helpers
(`hierarchical_pathfinder.gd`, `off_mesh_links.gd`, `navmesh_baker.gd`, `navmesh_carving.gd`)
with native code integrated into Godot's own navigation stack (Recast/Detour behind
`NavigationServer3D`). It is available when 3D is enabled.

## Classes

| Class | Purpose |
| --- | --- |
| `CgameNavmeshBaker` | Bakes tiles from triangle soups through `NavigationServer3D.bake_from_source_geometry_data(_async)`. The GDScript config keys are mapped onto `NavigationMesh` properties. Returns a `NavigationMesh` plus the 2D polygon dictionary format (`origin`, `size`, `polygons`, `heights`). |
| `CgameOffMeshLinkGenerator` | Drop / jump / gap link generation from heightfields; optionally creates `NavigationServer3D` links (the primitive behind `NavigationLink3D`) on a map. |
| `CgameHierarchicalPathfinder` | HPA* over a walkability grid for coarse planning across streamed regions, plus `plan_on_map()` which chains `NavigationServer3D.map_get_path` over region corridors. |
| `CgameDynamicCarver` | Budgeted tile carving with the GDScript-compatible polygon API. Mirrors obstacles as server obstacles, exports them as carving projected obstructions (`NavigationMeshSourceGeometryData3D`, the data behind `NavigationObstacle3D` carving) and calls a rebake callable per re-carved tile. |

## Behaviour notes

- Server-dependent calls (`bake_*`, `create_links_on_map`, `plan_on_map`, `set_server_map`) are
  guarded: with a dummy `NavigationServer3D` they return empty results (`baked == false`,
  0 links, empty paths) instead of erroring. Pure helpers (polygon conversion, HPA* on grids,
  link generation, carving) work without a server.
- Source triangles use the GDScript convention (counter-clockwise from above is walkable) by
  default; pass `godot_winding = true` to `make_source_geometry()` for Godot's clockwise faces.
- Each tile is baked with an overscan of agent radius + 3 cells and clipped to the exact tile
  rectangle, as in the GDScript baker, so tiles share border edges.
- The Recast bake replaces the GDScript voxelizer: polygon output is equivalent in shape but not
  vertex-identical to the GDScript baker.

## GDScript facade

`game_facade/cgame_navigation_facade.gd` prefers the native classes through `ClassDB` and falls
back to the GDScript implementations (`force_gdscript = true` forces the fallback).

## Tests

Doctest cases live in `tests/test_cgame_navigation.h` (`[CgameNavigation]`): HPA* around walls,
unreachable goals, dynamic cluster invalidation and route caching, world-space waypoints,
off-mesh link generation, tile/`NavigationMesh` conversion, carving budget queue, path routing
around carved walls and obstruction export. Server-dependent cases skip when the server is a
dummy.

```sh
scons platform=macos target=editor tests=yes -j8
./bin/godot.macos.editor.arm64 --headless --test --test-case="*[CgameNavigation]*"
```

**Validation status:** every translation unit was syntax-checked with clang (`-fsyntax-only`),
but a full build and the test run were not executed in the authoring environment. A real
`NavigationServer3D` bake (`CgameNavmeshBaker.bake_tile`) is untested.
