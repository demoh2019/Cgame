# Native HeightmapTerrain3D (first milestone)

This module adds a native `HeightmapTerrain3D` node to Godot when 3D is enabled.
It is intentionally distinct from the third-party Terrain3D add-on, so both
can coexist in one project.

## Use in the editor

1. Build the Godot editor with the module enabled (default with 3D support).
2. Add a **HeightmapTerrain3D** node to a scene.
3. Select it in the scene tree. The 3D toolbar offers Navigate, Raise, Lower,
   Smooth and Paint Color; adjust radius (in grid cells) and strength.
4. Left-drag on the heightfield. Each stroke is Undo/Redo-aware.
5. Change `grid_size` (2..257 along each axis) or `cell_size` in Inspector.
   Changing `grid_size` resets the stored height/color arrays.
6. Save the scene. Height and color arrays are serialized; the generated mesh
   is recreated when the scene loads.

Optional scripting:

```gdscript
var terrain := HeightmapTerrain3D.new()
terrain.grid_size = Vector2i(65, 65)
terrain.cell_size = 2.0
terrain.sculpt(Vector2(32, 32), 12.0, 4.0)
terrain.paint_color(Vector2(32, 32), 8.0, Color.DARK_GREEN, 0.5)
add_child(terrain)
```

The `erode_thermal(iterations, talus, strength)` method applies a four-neighbor
thermal erosion algorithm with simultaneous updates. This is not hydraulic erosion.

The `import_heightmap(image, minimum, maximum)` method takes an uncompressed
Image and maps its luminance into the supplied height range.

## Run tests

```sh
scons platform=linuxbsd target=editor dev_build=yes tests=yes -j$(nproc)
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case='*[Terrain3D]*'
```

## Physics collision snapshot

When 3D physics is compiled in, \`create_collision_shape()\` returns a
\`ConcavePolygonShape3D\` matching the current render-mesh triangles.

\`\`\`gdscript
var terrain: HeightmapTerrain3D = $HeightmapTerrain3D
var body := StaticBody3D.new()
terrain.add_child(body)
var collision := CollisionShape3D.new()
body.add_child(collision)
collision.shape = terrain.create_collision_shape()
\`\`\`

This is a **snapshot**, not a persistent physics proxy. After modifying the
terrain heightfield, update \`collision.shape = terrain.create_collision_shape()\`.
Prefer static scene geometry: concave triangle meshes are not appropriate for
dynamic rigid bodies. The method is unavailable when \`disable_physics_3d=yes\`.

## Deliberately out of scope

This milestone is a **single mesh** (no tessellation, tiles, LOD or world
partition). Each brush edit fully rebuilds it, so the current cap is 257²
vertices. It has no automatic collision node, vegetation scattering, eroded terrain
generator or material-layer splatmaps. Follow-up work should add chunked
geometry, collision/navmesh integration, multiple texture layers and asset
streaming before pursuing kilometer-scale worlds.

Compatibility: the node class is named `HeightmapTerrain3D` (not `Terrain3D`)
to avoid colliding with the existing Terrain3D GDExtension.
