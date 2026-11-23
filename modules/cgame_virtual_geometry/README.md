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

## P1 meshlet page payloads (new)

`CgameMeshletPages.build_pages(vertices, indices, page_bytes=16384)` packs
the existing native meshoptimizer meshlets into **bounded binary pages**
(1 KiB–64 KiB) with a stable little-endian v1 layout:

- 32-byte header (CGMP magic, version, first meshlet, count, three
  stream offsets, total page bytes);
- 48-byte descriptors (global vertex reference and local triangle stream
  offsets/counts, bounding sphere, normal cone);
- original uint32 **vertex IDs** into the unchanged imported source mesh,
  followed by uint8 **local triangle vertex indices**.

Meshlets never straddle page boundaries; at most 128 descriptors are
packed per page. This is the asset serialization format required before
building physical GPU residency, GPU page feedback, indirect meshlet
draws, and material vertex-stream decoding. It is *not* GPU-driven
rendering, a GPU texture/page cache, or a claim of faster rendering.
Full source normals, tangents, UV, vertex colors, weights and materials
stay in the original vertex buffers; pages reference them via original
vertex IDs, without lossy repacking or parallel shading reconstruction.

`CgameMeshletPages.inspect_page(page)` validates the complete binary
layout and returns decoded meshlet descriptors for import tests, offline
quality checks and future software fallback. Out-of-range references,
bad offsets, corrupt headers and malformed stream lengths fail closed.

**Actual Albion After integration:** in debug builds,
**Ctrl+Shift+F8** inspects up to 8 distinct meshes from *loaded*
`aa_scenery_multimeshes` (`MultiMeshInstance3D` instances), builds
these pages only on demand, strictly reads them back and reports page,
meshlet, triangle and byte counts in game. No page allocation, GDScript
scene walk or upload occurs in the normal render frame. The existing
scenery MultiMeshes keep their current native LOD, PBR and materials.

Relevant tests:
`modules/cgame_virtual_geometry/tests/test_cgame_meshlet_pages.h`,
`game/tests/test_virtual_geometry_meshlet_pages.gd`,
`tests/scene/test_meshlet_page_contract.py` and
`.github/workflows/native-meshlet-page-serialization.yml`.

## P1: GPU-resident meshlet pages in the game rendering-device path

In addition to the native `CgameMeshletPages` CPU serialization ABI, the canonical game has an experimental fixed-slot **GPU resident page pool** in `game/scripts/client/meshlet_renderer.gd` and `game/scripts/shared/meshlet_page_streaming.gd`. It uploads up to a configurable per-frame budget of logical pages and uses existing task/mesh shaders for GPU visibility. The CPU still selects coarse pages, and source meshes are CPU-resident. Normal game models keep their PBR/material fidelity; a separate explicitly enabled debug draw uses the actual game rock. This is **not** GPU indirect rendering or on-disk async streaming. See [GPU Meshlet Residency](../../game/docs/P1_GPU_MESHLET_RESIDENCY.md).

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
- The legacy cluster DAG `build_hierarchy` simplification is still positions-only. The new standalone native surface helper considers normals/UV1 and retains all original vertex channels, but does not yet feed attribute penalties into the cluster DAG or produce compact GPU meshlet pages.
- The occlusion rasterizer is scalar C++ written so that compilers can auto-vectorize the row loops; there is no explicit SIMD or tile binning yet.
