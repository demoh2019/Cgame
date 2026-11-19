# Native terrain module (initial implementation)

This module introduces `TerrainMesh`, an editor-visible `PrimitiveMesh` resource for
small, single-grid landscapes. It is available as a mesh resource on
`MeshInstance3D` in Godot builds with 3D enabled.

## Usage

Create a `MeshInstance3D`, set its **Mesh** property to a new **TerrainMesh**
resource, then adjust `grid_size`, `cell_size`, and `height_scale`.

Select that `MeshInstance3D` in the 3D editor to reveal the **Paint Terrain**
toolbar. Toggle **Paint Terrain** on, choose **Raise**, **Lower**, or **Smooth**,
then drag with the left mouse button over the mesh. Configure brush radius
(in heightmap cells) and strength from the toolbar. Each drag records a single
Undo/Redo action. Alt- and Ctrl/Command-click are left to the editor's viewport
navigation controls. Disable the toggle to restore ordinary selection.

The toolbar uses exact local-space triangle intersection to follow the rendered
terrain, including translated, rotated, and nonuniformly scaled mesh nodes.
Very large grids or repeated rapid brush updates may still be slow because
the current prototype rebuilds the whole mesh and uses an unchunked raycast.

Scripting the heightfield works in regular GDScript or an `@tool` script:

```gdscript
var terrain := TerrainMesh.new()
terrain.grid_size = Vector2i(65, 65)
terrain.cell_size = 2.0
terrain.height_scale = 1.0
terrain.sculpt(Vector2(32, 32), 12.0, 5.0)  # Raise a hill.
terrain.smooth(Vector2(32, 32), 8.0, 0.2)  # Soften the peak.
terrain.erode(12, 0.1, 0.5)  # Basic thermal erosion.
$MeshInstance3D.mesh = terrain
```

All height-editing methods operate on grid coordinates, not world meters.
`terrain.heights` is stored row-major (X within Z) as a
`PackedFloat32Array` and is persisted with the resource. Changes automatically
regenerate the mesh through `PrimitiveMesh`. New samples initialize to zero
when the grid expands. Values outside the grid are rejected by `get_height`
and `set_height`; `sample_height` clamps to the grid edges.

### Implemented

- Native C++ mesh registered as `TerrainMesh`, exposed through Inspector and
  scripts on 3D builds.
- Heightmap serialization, configurable rectangular grid/spacing/scale.
- Generated vertex positions, upward-facing triangle indices, normals and UVs.
- Individual vertex editing; bilinear height queries.
- Raise/lower brush with linear falloff; neighborhood smoothing with a
  snapshot (order-independent per brush application).
- Deterministic, conservative thermal erosion with configurable talus.
- 24 native automated test cases under `modules/terrain/tests`, including
  real save/load round-trips and ray picking.

### Not implemented yet

This is **not** a replacement for Terrain3D or Unreal landscape tools.
Texture painting layers, tiled/LOD rendering,
mass foliage scattering, collision updates, GPU streaming, erosion
simulations beyond the simple thermal model, and World Partition remain
separate features. The current mesh rebuilds the full grid after a change:
use moderate grid sizes, and do not assume it scales to enormous worlds.

### Testing

Build a Godot editor with tests enabled, then run the module test cases:

```sh
scons platform=linuxbsd target=editor dev_build=yes tests=yes
./bin/godot.linuxbsd.editor.dev.x86_64 --test --test-case="*[TerrainMesh]*"
```

The module is excluded from `disable_3d=yes` builds. Verify with the normal
Godot CI matrix (especially regular and double-precision Linux builds)
before merging.
