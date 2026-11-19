# Open World Toolkit — prototype for Godot 4.8 beta

**Status: experimental editor add-on (NOT integrated into Godot core).**

This directory is a standalone Godot project within the engine fork. Open
`misc/open_world_toolkit/project.godot` in the Godot editor; the plugin is already
enabled in the example project. To install into another Godot project, copy
`addons/open_world_toolkit` and enable **Project → Project Settings → Plugins**.

## Features (first vertical slice)

- `OWHeightmap` — heightfield with deterministic noise generation, radial
  sculpting (raise, lower, smooth, flatten), 2-layer texture masks and
  conservative thermal erosion.
- `OWTerrain3D` — generated mesh, normals, UVs and vertex colors, shader blending
  two color/texture layers; CPU raycast used for viewport painting.
- `OWTerrainBrushDock` — editor dock for painting with a mouse in the 3D viewport,
  noise/erosion buttons, Godot editor undo/redo on completed strokes.
- `OWFoliageScatter3D` — seeded multi-mesh foliage scatter with elevation/slope
  filters and instance cap (assign a mesh and link a terrain node first).
- `OWWorldPartition3D` — runtime grid-cell streaming of assigned PackedScene
  resources around a viewer, with separate load/unload radii and support for
  negative world coordinates.

### Editor workflow

1. Open the demo project. In the Scene tree select `Terrain`.
2. In the **World Terrain** dock, enable **Sculpt in 3D viewport**.
3. Pick a brush, radius and strength. Left-drag to paint/sculpt. Use Godot's
   Undo/Redo for the stroke. `Generate heightfield` replaces heights with
   noise; `Apply thermal erosion` smooths sharp slope differences.
4. Set `ground_texture`/`detail_texture` on the terrain node if you want
   image-based materials. The brush's layer modes paint the red vertex-color
   channel used as the 2-texture blend weight.
5. To scatter vegetation, add `OWFoliageScatter3D` to the scene, link `terrain`,
   assign `foliage_mesh`, and click **Scatter linked foliage**. Save the scene.
6. To stream an authored world, create `OWWorldCell` resources with coordinates
   and scene paths, assign them to an `OWWorldPartition3D` instance, and set
   `viewer_path` to a camera/player node.

## Tests

```bash
godot --headless --path misc/open_world_toolkit --script res://tests/run_tests.gd
```

The GDScript suite exercises 35 test cases across grid storage, bilinear
sampling, normals, brush shapes, blending, conservative erosion, noise,
undo snapshots, generated mesh geometry, ray picking, foliage and cell math.
The workflow in `.github/workflows/open-world-toolkit.yml` uses Godot 4.8 beta4.

## Known limitations / next tasks

- This is an add-on demo, not a built-in engine editor panel or a replacement for
  Terrain3D. It only supports a **single heightfield mesh**, not clipmap LOD,
  sparse infinite terrain, physics collision, or full material splatmaps.
- Texture blending is vertex-resolution; collision is **not generated**. The
  runtime world streamer uses explicit scene resources and synchronous loads,
  not background resource streaming or HLOD. Far-away assets need manual LOD.
- No Niagara-like PCG graph, water, vegetation authoring, cloud simulation,
  Nanite/Lumen, hardware RT, rollback or ECS is provided here yet.
- For the core fork, first validate this editor workflow and GDScript tests;
  then port stable functions to a `modules/` C++ implementation if desired.
- Check performance on >257x257 grids. Continuous mouse motion currently
  regenerates the whole mesh; future work should use dirty chunk updates.
- The demo can be opened with GL Compatibility; the scene is intentionally
  simple so the same tests can run in headless environments.

## AI disclosure

This first prototype and the tests were authored with AI assistance and need
human review. No code from commercial engines was copied.