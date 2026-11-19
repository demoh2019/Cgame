# Native heightmap terrain (initial implementation)

This module adds **HeightmapTerrain3D**, a native scene node with a serializable **TerrainHeightmap** resource. It is compiled into Godot by default for builds with 3D enabled.

The goal of this first increment is to provide a small but usable engine-integrated terrain editor, not to replace the existing third-party Terrain3D extension. The native class names are intentionally distinct to avoid a collision with the extension.

## Getting started

1. Build the Godot editor with the module enabled (default on 3D builds).
2. Add a **HeightmapTerrain3D** node to any 3D scene. A 17×17 flat heightmap is created automatically.
3. Select the node. The 3D toolbar offers **Raise**, **Lower**, and **Paint Color** modes, a brush radius, strength, and color picker.
4. Left click on the visible terrain to apply the brush. Alt/Ctrl/Shift + click remains available to viewport tools. Use Undo/Redo to revert each stroke.
5. In the Inspector, expand the **Heightmap** resource to adjust **width** and **depth** (2–513 samples). **Cell Size** controls world-unit spacing. Assign **Terrain Material** to replace the built-in vertex-color material.

### Procedural example (GDScript)

```gdscript
var terrain := HeightmapTerrain3D.new()
terrain.heightmap.set_dimensions(129, 129)
terrain.cell_size = 2.0
terrain.heightmap.apply_height_brush(Vector2(64, 64), 25.0, 12.0)
terrain.heightmap.apply_color_brush(Vector2(64, 64), 20.0, Color.DARK_GREEN, 0.8)
add_child(terrain)
```

### Import an Image heightmap

```gdscript
var image := Image.load_from_file("res://heightmap.png")
var terrain := HeightmapTerrain3D.new()
terrain.heightmap.import_height_image(image, -10.0, 70.0)
add_child(terrain)
```

The image must be uncompressed and 2–513 pixels along each dimension. Single-channel grayscale/R images use the red channel as height; RGB images use luminance. Values are clamped to 0–1 before mapping into the requested height range.

## Design choices and limitations

- Uses one continuous triangle mesh with **correct winding**, computed normals, UVs, and vertex colors.
- Height/color changes are serialized in the heightmap resource; all nodes sharing the resource receive change notifications.
- Radius is given in world units in the editor and grid units in the resource API.
- Brushes use radial falloff. Each mouse click is a discrete Undo/Redo action; continuous drag painting is not yet provided.
- The current implementation rebuilds the **entire mesh** after edits. It is deliberately capped at **513×513 samples** to prevent accidentally creating an unbounded mesh.
- Terrain collision is **not updated automatically**. To add static collision, use the inherited MeshInstance3D collision tools and regenerate it after terrain edits.
- Color painting currently writes vertex colors, **not** blended multi-texture terrain layers. Assign a ShaderMaterial with vertex-color support for custom shading.
- Erosion, streaming, grass/trees, GPU-driven rendering, HLOD, PCG graphs, World Partition, caves, and advanced terrain shaders are **not included** in this PR.

## Test plan

The module includes `modules/heightmap_terrain/tests/test_heightmap_terrain.h`. Tests are compiled automatically with `tests=yes`.

```sh
scons platform=linuxbsd target=editor tests=yes module_mono_enabled=no
./bin/godot.linuxbsd.editor.x86_64 --headless --test --test-case='*[Terrain]*'
```

A dedicated GitHub Actions workflow builds the full editor and runs targeted plus full C++ tests.

## Roadmap linked to the 48 requested improvements

1. **Terrain MVP (this PR):** heightmap resource, mesh generation, basic sculpt/color brush.
2. **Terrain painting:** proper multi-layer splat maps, material blending, textured brush previews.
3. **Foliage:** GPU-instanced placement with density masks and deterministic scattering.
4. **Terrain scalability:** chunk rebuilds, LOD transitions, streaming, origin rebasing and HLOD.
5. **PCG:** deterministic asset graphs that consume heightmaps and scatter points with dependency-aware caching.
6. **Water and erosion:** interoperable terrain height modifiers and water masks.
7. **Core/render/network/tooling:** separate, testable PRs for the remaining features rather than one unreviewable monolithic patch.

Each stage needs regression tests, compatibility evaluation, performance benchmarks, and review before merge.
