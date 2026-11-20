# Environment art expansion — 20 November 2026

## Assets and provenance

- 26 Kenney low-poly GLB models, source: [Hidencod/tge-assets](https://github.com/Hidencod/tge-assets), all CC0 1.0. Models are self-contained; no external textures or runtime downloading.
- 2 extra Poly Haven material sets (4 JPEG files): [brick_wall_001](https://polyhaven.com/a/brick_wall_001) and [weathered_plank_siding](https://polyhaven.com/a/weathered_plank_siding), CC0 1.0. Original artwork was redistributed in downsized JPEG form by [California Drive](https://github.com/roszhan2684/california-drive/blob/main/ASSET_LICENSES.md).

## In-game integration

- Extra trees join default Kenney tree variants, even when optional external Quaternius packs are missing.
- Ground decorations are deterministic chunk-scattered MultiMeshes around trees, rock nodes and meadows. Graveyard and demolished siege objects appear only near actual ruins.
- Brick and plank terrain now occupy layers 11–12 in the existing 13-layer textured ground shader; city site patches use brick, docks use planks. Bunkers and depots retain concrete.
- Ground normals use OpenGL-oriented normal maps (`*_nor_gl.jpg`). Distances, small probabilities and instancing limit visible clutter.

## Validation

Run from a local Godot 4 editor, after import has finished:

```sh
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/test_environment_assets.gd
godot --headless --path game --script res://tests/run_all.gd
```

For the first direct test, `test_environment_assets.gd` is a test suite with `run(t)` and should be run through the existing `run_all.gd` test harness instead. Verify imported meshes in a live game scene at a woodland area, a ruined city and a dock, and profile overdraw/frame time on integrated GPUs. Note that no Godot executable was available in the editing environment at the time of this commit.
