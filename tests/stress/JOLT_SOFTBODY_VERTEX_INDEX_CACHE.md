# Jolt SoftBody3D: cached mesh-index to physics-vertex mapping

Jolt soft bodies are created by converting Godot's indexed triangle mesh to
`SoftBodySharedSettings`, welding vertices at identical `Vector3` positions,
constructing constraints, and calling Jolt's `Optimize()` to reorder the
constraints for parallel solving.

Previously Cgame performed a position-hash lookup for **every triangle
corner**, even though a typical indexed grid references the same mesh vertex
four or more times. The existing `mesh_to_physics` array, initialized to
`-1`, was only written and never used as a cache during conversion.

## Implementation

- Check `mesh_to_physics[mesh_index]` first. A nonnegative value means the
  mesh vertex was already mapped: use it with **no position-hash lookup**.
- On first reference, use a compact open-addressed
  `AHashMap<Vector3, int>` to weld mesh indices sharing the same position.
  Preserve first-occurrence order, Jolt face winding, degenerate triangle
  skipping, per-vertex weights, and `mesh_to_physics` remapping through
  `SoftBodySharedSettings::Optimize()`.
- Reserve sufficient hash-table slots for at most
  `min(vertex_count, triangle_corner_count)` unique referenced vertices,
  taking the map's approximately 75% load threshold into account. This
  avoids mid-build rehashes without retaining a persistent cache across
  scene resources.
- The hash table is temporary, destroyed when the conversion finishes.
  Nonindexed/unreferenced mesh vertices retain their original semantics:
  unused indices remain `-1`.

For a 32x32 indexed grid (31x31 quads / 5766 triangle corners), the reference
model makes **1024 position-hash lookups** rather than 5766. This is a count
of removed hash operations, **not** a measured physics speedup.

Jolt's simulation uses its separate `SoftBodySharedSettings::Optimize()`
routine, so the actual solver and its constraint reordering are unchanged.

## Tests

```sh
python3 -m unittest tests/stress/test_jolt_softbody_vertex_index_cache.py -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
  --script res://physics_jolt_softbody_vertex_dedup_regression.gd
```

The Python test compares the exact vertex mapping, welded vertex count and
face order against the original per-corner position-hash logic for 400
deterministic randomized indexed meshes, including repeated mesh indices
and duplicate positions. It also checks the dense grid case and the C++
lookup order.

The native Jolt fixture creates a 24x24 grid with a duplicated position
for each mesh vertex; two adjacent triangle lists use the original and
duplicate indices. It creates **nine** soft bodies in three waves,
advances physics, and confirms that original and duplicate probes resolve
to the same world-space vertex, while observing memory and runtime.

Native CI syntax-checks this GDScript, selects the **Jolt Physics** backend,
builds the changed C++ source and runs the fixture. When reviewing
performance, compare construction time, allocator traffic and peak RSS
on the same machine and build, with scene loads repeated multiple times.
No measured improvement is claimed until native CI and benchmarks finish.

## Future work

The current soft-body mesh conversion fetches render mesh data through
`RenderingServer` during `_create_shared_settings()`. A source TODO
indicates potential deadlock when a separate physics thread and main-thread
synchronization are used. That requires a more substantial, main-thread
staging/lifetime solution and is **not** addressed by this patch.
