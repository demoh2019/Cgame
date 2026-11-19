# Native TerrainHeightmap (experimental foundation)

This built-in engine module adds a serializable `TerrainHeightmap` resource and an editor-visible `HeightmapTerrain3D` node (named to avoid clashing with the popular Terrain3D extension). The resource provides deterministic CPU algorithms:

- Height field storage, safe dimension changes and bilinear sampling.
- Sculpt and smooth brushes with radial falloff.
- Conservative thermal/talus erosion (not hydraulic erosion).
- Four RGBA vertex-paint layers that always remain normalized.
- Indexed ArrayMesh generation with normals, UVs and vertex color weights.
- Bounded chunk mesh generation with LOD strides and global UVs/normals.
- Batched edits with nested `begin_edit()` and `end_edit()` to avoid repeated mesh rebuilding.
- Seeded foliage candidate scattering with slope/height filtering.
- In-engine C++ doctest suites in `tests/test_terrain_heightmap.h`, `tests/test_terrain_3d.h`, `tests/test_terrain_chunks.h`, and `tests/test_terrain_scatter.h`.

## Minimal GDScript example

```gdscript
extends Node3D

func _ready() -> void:
    var terrain := HeightmapTerrain3D.new()
    add_child(terrain)
    var data := terrain.terrain_data
    data.dimensions = Vector2i(129, 129)
    data.sculpt(Vector2(64, 64), 30.0, 16.0)
    data.smooth(Vector2(64, 64), 12.0, 0.2)
    data.paint_layer(Vector2(64, 64), 15.0, 1, 1.0)
    terrain.cell_size = 2.0
    # The node automatically regenerates its mesh after resource edits.
```

For the paint layers to be visible as textures, assign a shader/material that blends four textures using `COLOR.rgba`. Otherwise standard vertex color behavior (if used by the material) applies. An example shader is in `examples/four_layer_terrain.gdshader`.

For large worlds, use `build_chunk_mesh(origin, cell_count, lod_stride, cell_size)` to generate smaller meshes. Place each mesh instance at the matching `Vector3(origin.x * cell_size, 0, origin.y * cell_size)` offset. The optional `examples/chunked_terrain.gd` provides **camera-centered chunk creation and release**, but the source heightmap remains resident in memory and mixed LOD edges may have cracks. This is not a full World Partition implementation.

To edit multiple points without redundant rebuilds, call `terrain.begin_edit()` before a sequence of brush operations and `terrain.end_edit()` afterward (always pair them; nested edits are supported).

Foliage scattering: `terrain.scatter_points(seed, spacing, jitter, max_slope, min_height, max_height, cell_size)` returns stable candidate positions. See `examples/procedural_foliage.gd` for efficient rendering via `MultiMeshInstance3D`. It does not build plant meshes or include collision.

`build_mesh()` returns a new mesh. `HeightmapTerrain3D` automatically connects to the resource's `changed` signal and rebuilds after edits. When using a plain `MeshInstance3D`, call `instance.mesh = data.build_mesh(cell_size)` explicitly. Resource data can be saved into a `.tres` or a `.tscn` via the normal Godot ResourceSaver / scene serializer.

### Performance and project scope

This first increment is for **small-to-medium single-grid terrains**. The 1,048,576-vertex cap bounds memory consumption, but large grids may still be expensive to rebuild. Each current brush is O(width × depth), and erosion is O(iterations × width × depth). For changing many samples use a batch edit. Do not rebuild every frame. Scattering is limited to 65,536 candidate positions per call.

Not yet included: viewport Terrain Editor brush UI, editor undo/redo brush integration, automatic chunk collision and seam stitching, production-grade disk streaming or partitioning, procedural tree geometry, physics collision, hydraulic erosion, procedural graph, virtual textures, or GPU-driven rendering. Those are separate features. The module alone is not a replacement for Terrain3D.

### Tests

Compile an engine with tests enabled and the terrain module enabled, then run:

```shell
scons platform=linuxbsd target=editor tests=yes module_terrain_enabled=yes
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[TerrainHeightmap]*"
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[HeightmapTerrain3D]*"
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[TerrainChunks]*"
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[TerrainScatter]*"
```

The exact binary suffix and test flags depend on the target platform and build configuration. Run the entire Godot test suite for integration regressions.
