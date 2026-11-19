# Native TerrainHeightmap (experimental foundation)

This built-in engine module adds a serializable `TerrainHeightmap` resource and an editor-visible `HeightmapTerrain3D` node (named to avoid clashing with the popular Terrain3D extension). The resource provides deterministic CPU algorithms:

- Height field storage, safe dimension changes and bilinear sampling.
- Sculpt and smooth brushes with radial falloff.
- Conservative thermal/talus erosion (not hydraulic erosion).
- Four RGBA vertex-paint layers that always remain normalized.
- Indexed ArrayMesh generation with normals, UVs and vertex color weights.
- In-engine C++ doctest coverage in `tests/test_terrain_heightmap.h`.

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

`build_mesh()` returns a new mesh. `HeightmapTerrain3D` automatically connects to the resource's `changed` signal and rebuilds after edits. When using a plain `MeshInstance3D`, call `instance.mesh = data.build_mesh(cell_size)` explicitly. Resource data can be saved into a `.tres` or a `.tscn` via the normal Godot ResourceSaver / scene serializer.

### Performance and project scope

This first increment is for **small-to-medium single-grid terrains**. The 1,048,576-vertex cap bounds memory consumption, but large grids may still be expensive to rebuild. Each brush is O(width × depth), and erosion is O(iterations × width × depth). Do not rebuild every frame.

Not yet included: viewport Terrain Editor brush UI, editor undo/redo brush integration, chunked LOD, world streaming, foliage placement, physics collision, hydraulic erosion, procedural graph, virtual textures, or GPU-driven rendering. Those are separate features. The module alone is not a replacement for Terrain3D.

### Tests

Compile an engine with tests enabled and the terrain module enabled, then run:

```shell
scons platform=linuxbsd target=editor tests=yes module_terrain_enabled=yes
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case="*[TerrainHeightmap]*"
```

The exact binary suffix and test flags depend on the target platform and build configuration. Run the entire Godot test suite for integration regressions.
