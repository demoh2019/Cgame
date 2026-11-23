# Cgame Virtual Geometry (experimental)

Native building blocks for Nanite-style virtualized geometry on the CPU. This is a **toolkit**, not a renderer: it produces and culls clusters; drawing the selected clusters is up to the game (for example by assembling an `ArrayMesh` from a cut).

| Class | Purpose |
|---|---|
| `CgameMeshlets` | Splits an indexed mesh into meshlets (`meshopt_buildMeshlets`), bounding sphere and normal cone (`meshopt_computeMeshletBounds`), `cone_cull`, `frustum_cull`. |
| `CgameClusterLOD` | Cluster DAG: group neighbouring clusters, simplify with `meshopt_simplify` + `meshopt_SimplifyLockBorder`, re-split into meshlets. `select_cut` picks a crack-free set by projected screen-space error; `triangle_count`. |
| `CgameOcclusionRaster` | Low-resolution software depth rasterizer with a max-depth Hi-Z pyramid. `rasterize_occluder`, `is_visible`, `test_many`, `temporal_reproject`. Conservative: unsure means visible. |

All classes mirror the GDScript reference implementations (`scripts/shared/meshlets.gd`, `cluster_lod.gd`, `occlusion_raster.gd`) and use the same dictionary keys and semantics. Meshlet and cluster methods are `static`.

## Dependencies

Requires the `meshoptimizer` module (vendored in `thirdparty/meshoptimizer`). If that module is disabled, `SCsub` compiles the needed library sources itself. Enabled whenever 3D is enabled (`disable_3d=no`).

## Conventions

- Godot winding (clockwise front faces). `cone_axis` is the outward normal, so `cone_cull` uses `dot(center - cam, axis) >= cutoff * |center - cam| + radius`.
- Meshes passed to `CgameClusterLOD` must be welded (neighbouring triangles share vertex ids).
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

## P1: Attribute-fidelity meshoptimizer surface simplification

The native static method `CgameClusterLOD.simplify_surface_arrays(surface_arrays,
target_triangles, normal_weight=0.6, uv_weight=0.6)` now offers an **opt-in**
normal/UV-weighted simplification path for a *complete Godot surface*. The
algorithm passes positions and available normals/UVs to
`meshopt_simplifyWithAttributes` with locked borders. It never modifies
the source vertex array: output differs **only in `Mesh.ARRAY_INDEX`**.
This preserves original normals, tangent frames and bitangent signs, UV1/2,
vertex colors, bones and weights, and custom vertex channels. The source
material is retained by the caller when constructing its new `ArrayMesh`.

The API rejects invalid array shape, out-of-range indices, a nonfinite
vertex/normal/UV, mismatched attribute length, oversized data, or
nonfinite/unbounded weights. If the target cannot be reached due to
topological restrictions, the caller receives a valid *reduced* index
list or an empty result if no reduction was possible. Callers must
check actual triangle count before adoption. Vertices are not compacted,
and there is no GPU geometry streaming/residency in this feature.

**Real Albion After integration:** the production
`game/scripts/client/model_catalog.gd` calls
`MeshLodPreservation.with_triangle_budget(...)` while loading/caching
small scattered meshes. In `game/scripts/client/mesh_lod_preservation.gd`,
a single-surface static mesh with no blend shapes or pre-authored LODs
now tries the new native weighted pass first. If it cannot hit the
triangular draw budget, if no native Cgame method is present, or for
multi-surface/animated meshes, the previous importer simplification is
used. This runs once per source mesh, never per frame. No gameplay
collision, server data, audio, skin deformation or network state changes.

Tests:
`modules/cgame_virtual_geometry/tests/test_cgame_virtual_geometry.h`,
`game/tests/test_virtual_geometry_attribute_lod.gd`,
`tests/scene/test_virtual_geometry_attribute_contract.py`, and the
`.github/workflows/native-virtual-geometry-attribute-lod.yml` workflow.
Source-level checks are not equivalent to successful native compilation
or graphics-driver testing.

## Cluster cut surface attribute fidelity

The separate `CgameClusterLOD.build_cut_arrays(source_arrays, hierarchy, cut)` API
returns the chosen indexed cluster cut while retaining **all original source
vertex streams** (normals, tangents, UVs, colors, skin and custom channels).
It validates that the hierarchy was built from those exact vertex positions.
It complements `simplify_surface_arrays`: the latter weights normals/UVs
when choosing new triangles, while cluster hierarchy cuts currently use
position-only simplification but preserve original vertex attributes.
This step is CPU-side; no GPU cluster residency or mesh shading is implied.

## P1: GPU-resident meshlet pages in the game rendering-device path

The main game now includes an experimental bounded page pool for Vulkan task/mesh shaders in `game/scripts/client/meshlet_renderer.gd`, `game/scripts/shared/meshlet_page_streaming.gd` and its GPU shader resources. It uploads fixed-size resident meshlet pages with a per-frame transfer budget, and the GPU task stage culls individual meshlets without visibility readback. The CPU retains source meshes and schedules coarse pages. Production models remain on their original material-aware rendering path: only an explicitly enabled debug draw of the actual game rock exercises this feature. This is a **game rendering-device feature**, not an extra C++ class in `cgame_virtual_geometry`. Details: [GPU Meshlet Residency](../../game/docs/P1_GPU_MESHLET_RESIDENCY.md).

## Limitations

- No GPU path and no streaming; hierarchy building is single threaded and intended for offline or load-time use.
- The legacy cluster DAG `build_hierarchy` simplification is still positions-only. The new standalone native surface helper considers normals/UV1 and retains all original vertex channels, but does not yet feed attribute penalties into the cluster DAG or produce compact GPU meshlet pages.
- The occlusion rasterizer is scalar C++ written so that compilers can auto-vectorize the row loops; there is no explicit SIMD or tile binning yet.
