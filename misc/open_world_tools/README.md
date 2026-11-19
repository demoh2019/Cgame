# Open World Tools — first implementation slice

This is a **working experimental Godot 4.x project/addon**, not a replacement for Terrain3D, Unreal Landscape, or the Godot rendering architecture. It is intentionally located outside the engine's core source tree (`misc/open_world_tools`) so it can be reviewed, tested, and iterated without adding unstable APIs to every Godot build.

## Implemented in this prototype

- **Heightfield terrain** (`WorldTerrain3D`): persistent `PackedFloat32Array` heights, bilinear sampling, normals, tiled/chunked terrain meshes, optional concave triangle-mesh collision, and heightmap image import.
- **Editor sculpting**: raise, Shift+lower, smooth, flatten, variable radius and strength, and scene Undo/Redo. A deliberately simple 3D ray-to-heightfield iteration places the brush. The brush updates the preview immediately.
- **Terrain painting**: editable vertex tint and four RGBA texture-blend weights. Set `use_texture_layers=true`, provide up to four textures, and paint weights using the *Paint Texture Layer* mode. Missing textures use a white fallback multiplied by per-layer tints.
- **Thermal erosion**: deterministic, mass-conserving exchange between neighboring height samples with talus and iteration controls via script API.
- **GPU foliage** (`WorldFoliage3D`): reproducible MultiMesh scatter using a seed, slope limit, random rotation and scale, and terrain-relative transforms.
- **Cell-based world streaming** (`WorldStreamer3D`): load/unload PackedScene cells around a moving focus in X/Z, including negative cell coordinates. It is synchronous and intended for small prototype cells only.
- **Automated tests**: Godot headless harness for data, sampling, brushes, painting, heightmap import, erosion, foliage, and streaming. A separate offline static test suite checks project packaging and code invariants.

## Try it

1. Open this directory (`misc/open_world_tools`) as a Godot project, or copy its `addons/open_world_tools` directory into an existing Godot project's `res://addons` directory and enable the plugin under **Project Settings → Plugins**.
2. Open `demo.tscn`, select `WorldTerrain`, then use the **Open World Tools** toolbar in the 3D editor. Select the brush mode, radius, and strength. Hold **Shift** while using *Raise* to lower ground.
3. For texture splat painting, enable `use_texture_layers` in the terrain node Inspector and assign textures `texture_0` through `texture_3`. Select *Paint Texture Layer* and choose the layer. The four channels are normalized by the shader.
4. To create foliage, add a `WorldFoliage3D` node, assign the terrain node and a Mesh, then select it and press **Scatter Foliage**.
5. To stream scenes, add `WorldStreamer3D`, set `focus` to the player/camera, and add `WorldStreamCell` resources to `cells` with grid coordinates and PackedScenes.

## Running tests

From this directory with a Godot 4.x executable available:

```bash
godot --headless --path . --script res://tests/test_world_tools.gd
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The headless script exits nonzero on assertion failure. **Only the Python static tests can run without a Godot binary.** A passing static test is not evidence that the GDScript executes or renders correctly; run Godot/CI before merging.

## Design boundaries / known limitations

- Meshes are regenerated per edit, not incrementally updated; large terrains will be slow. Chunking limits geometry size but does not provide LOD or GPU-driven clipmaps. There is no mesh stitching or HLOD yet.
- Texture painting stores **vertex weights**, so precision is limited by terrain resolution. It is not virtual texturing or image splatmaps.
- The ray/heightfield intersection in the editor is an approximation; steep slopes and near-horizontal camera rays may miss or misplace a brush. Undo/Redo stores full arrays per stroke (high memory use for large terrains).
- Foliage scatters in one MultiMesh; it does not use biome rules, occlusion, per-cell streaming, culling, or wind. Foliage must be re-scattered when heights change.
- Cell streaming is synchronous and has no prefetch, save-state persistence or async resource loader. A cell is represented by a scene with a position calculated from its grid coordinate.
- Physics collision on every edit is expensive and uses a trimesh shape for **static terrain only**.
- This addon is not integrated in the native Godot editor build; it is a portable prototype and a possible foundation for future core components if upstream design review supports that.

For a production terrain today, [Terrain3D](https://godotengine.org/asset-library/asset/5572) already provides mature clipmaps, LOD, vegetation, and texture painting and should be evaluated before expanding this prototype.

See [`ROADMAP.md`](ROADMAP.md) for the 48-feature scope, technical dependencies and priorities.