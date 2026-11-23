# Cgame Virtual Geometry (experimental)

Native building blocks for Nanite-style virtualized geometry on the CPU. This is a **toolkit**, not a renderer: it produces and culls clusters; drawing the selected clusters is up to the game (for example by assembling an `ArrayMesh` from a cut).

| Class | Purpose |
|---|---|
| `CgameMeshlets` | Splits an indexed mesh into meshlets (`meshopt_buildMeshlets`), bounding sphere and normal cone (`meshopt_computeMeshletBounds`), `cone_cull`, `frustum_cull`. |
| `CgameClusterLOD` | Cluster DAG: group neighboring clusters, simplify with `meshopt_simplify` + `meshopt_SimplifyLockBorder`, re-split into meshlets. `select_cut` picks a crack-free set by projected screen-space error; `triangle_count`. |
| `CgameOcclusionRaster` | Low-resolution software depth rasterizer with a max-depth Hi-Z pyramid. `rasterize_occluder`, `is_visible`, `test_many`, `temporal_reproject`. Conservative: unsure means visible. |

All classes mirror the GDScript reference implementations (`scripts/shared/meshlets.gd`, `cluster_lod.gd`, `occlusion_raster.gd`) and use the same dictionary keys and semantics. Meshlet and cluster methods are `static`.

## Dependencies

Requires the `meshoptimizer` module (vendored in `thirdparty/meshoptimizer`). If that module is disabled, `SCsub` compiles the needed library sources itself. Enabled whenever 3D is enabled (`disable_3d=no`).

## Conventions

- Godot winding (clockwise front faces). `cone_axis` is the outward normal, so `cone_cull` uses `dot(center - cam, axis) >= cutoff * |center - cam| + radius`.
- Meshes passed to `CgameClusterLOD` must be welded (neighboring triangles share vertex ids).
- `CgameClusterLOD` error values are absolute object-space distances (meshoptimizer `meshopt_SimplifyErrorAbsolute`).
- Occlusion depth is clip-space `w` (view distance); perspective projections only.

## Example

```gdscript
var h := CgameClusterLOD.build_hierarchy(vertices, indices, 4)
var cut := CgameClusterLOD.select_cut(h, camera.global_position, deg_to_rad(camera.fov), 1080.0, 1.0)
print(CgameClusterLOD.triangle_count(h, cut))
```

Use `game_facade/cgame_virtual_geometry_facade.gd` to call the native classes with an automatic fallback to the GDScript implementation when the module is not compiled in.

## Tests

`tests/test_cgame_virtual_geometry.h` (doctest) mirrors `test_virtual_geometry.gd` and `test_occlusion_culling.gd`: meshlet limits and coverage, cone/frustum culling, monotonic cluster errors, far cut has fewer triangles, watertight cuts, determinism, and an occluded box behind a wall. Run with `./bin/godot.<platform>.editor.<arch> --test --test-case="*Cgame*"`.

## Draw-ready cluster cut preserving all vertex attributes

`CgameClusterLOD.build_cut_surface(hierarchy, cut, surface_arrays)`
combines a selected cut into an indexed triangle surface suitable for Godot's
`ArrayMesh.add_surface_from_arrays`. It keeps original vertex indices
and every imported vertex stream *unchanged* (normals, tangents, UVs,
vertex colors, skinning and custom channels), so PBR materials do not
lose their tangent space. It rejects malformed or mismatched sources,
out-of-range cluster indices, repeated ids and oversized cuts.

The game's `game/scripts/client/pcg_world_dressing.gd` uses this
API for cached, medium-size distant PCG props where cluster reduction
is substantial. A cheap box proxy remains for small, unsupported,
oversized and non-simplifying assets or stock Godot.

**Not yet Nanite:** this renders via the regular Godot GPU mesh
pipeline; it does not GPU-cull meshlets, stream mesh pages, perform
indirect draws or reduce original vertex-buffer residency.

## Limitations

- No GPU path and no streaming; hierarchy building is single threaded and intended for offline or load-time use.
- Simplification ignores normals, UVs and other attributes (positions only).
- The occlusion rasterizer is scalar C++ written so that compilers can auto-vectorize the row loops; there is no explicit SIMD or tile binning yet.
