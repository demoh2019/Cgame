# P1 Nanite groundwork: imported mesh attribute fidelity

## Why this implementation comes before full GPU-driven virtual geometry

Unreal Engine Nanite preserves shading attributes while choosing which
clusters to render. Cgame already has `CgameMeshlets`, a cluster LOD DAG
and conservative CPU occlusion raster. However, its older
`CgameClusterLOD.build_hierarchy()` simplification uses **positions only**.
It is not a GPU Nanite replacement.

This P1 increment adds a separate native
`CgameClusterLOD.simplify_surface_arrays(surface_arrays, target_triangles,
normal_weight=0.6, uv_weight=0.6)` helper, using
`meshopt_simplifyWithAttributes` from the existing meshoptimizer dependency.
It penalizes simplification that distorts the original vertex normals and
UV coordinates, and locks topology borders to reduce seam damage.

**Important correctness guarantee:** returned Godot surface arrays refer
to the **original vertex IDs** and preserve all source channels (vertex
position, normals, tangent vectors/signs, UV/UV2, vertex colors, bones,
weights and custom attributes). Only triangle indices change, and the
original resource is not mutated. This means no destructive vertex
welding, tangents regenerated with an inconsistent handedness, or losing
material texture coordinates during decimation. This is visual/index
preservation, not proof that the simplified shape has identical shading.

## Immediate production Albion After use

`ModelCatalog.entry_mesh()` already builds a mesh cache and invokes
`MeshLOD.with_triangle_budget(...)` for small roots, sticks, rubble and
decorative objects that repeat many times per streamed chunk.

`game/scripts/client/mesh_lod_preservation.gd` now first tries the native
attribute-aware surface simplification on eligible **single-surface,
static, indexed, no-existing-LOD** assets, accepting it only when the
actual reduced index count meets the requested budget. It constructs a new
`ArrayMesh` with the authored material, surface name, AABB and original
attributes. It then proceeds through existing
`MeshLOD.with_generated_lods()` logic when applicable.

Multi-surface, animated, already-prepared meshes, unsupported Cgame
binaries and stock Godot keep the original `ImporterMesh` path.
Results are cached per source mesh, never recalculated each frame.
Physics, networking, loot, collision and character skeletons are
untouched.

## Tests and truthful current limits

Native tests reject invalid indexes, NaN, malformed attribute arrays and
weights, and verify all source channels are bit-identical after
simplification. Headless game tests exercise the **actual model catalog**
triangle-budget call chain, imported PBR materials, normal/UV2/tangent
streams, triangle caps, source immutability and engine fallback.

This is **not yet** Nanite. Production-grade GPU virtualized geometry needs:
- Meshlet packing and variable-size page format with position, tangent,
  UV, normal, material and custom-attribute decoding;
- page-aware cluster DAG/cross-page dependency tree and persistent
  asset-level streaming;
- compute visibility, occlusion and draw compaction on actual GPUs;
- GPU-resident page allocator, memory budget and renderer feedback;
- software/compatibility fallback and a cross-driver performance suite.

No frame-rate increase or full fidelity guarantee is claimed without
imported production asset comparisons and hardware captures.

Reference:
https://dev.epicgames.com/documentation/en-us/unreal-engine/nanite-virtualized-geometry-in-unreal-engine
