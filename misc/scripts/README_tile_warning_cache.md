# TileMap missing-tile overlay — CPU and allocation reduction

Cgame cherry-picks [Godot PR #124288](https://github.com/godotengine/godot/pull/124288), which was **open** when reviewed on 2026-11-19, with two additional performance/correctness refinements.

## Performance changes

The previous `TileMapLayerEditor::_draw_overlay` obtained every used cell and rechecked its source/atlas/alternative on **each redraw**, including offscreen tiles, before drawing the missing-tile warnings. For large tilemaps this ran on every canvas pan/zoom and consumed time proportional to the complete map.

- Maintain the missing-tile list until `TileMapLayer` cell content or related editor state changes. The overlay draws only cached **invalid tiles**, culling to the visible rectangle (expanded to include partially visible tiles).
- Add an editor-only `cell_data_revision` to `TileMapLayer`. Real `set_cell` updates increment it; idempotent calls and missing-cell erasures do not.
- Refresh the cache when the revision changes or the layer emits `changed`.
- **Cgame-specific:** rebuild using a read-only reference to the existing `HashMap<Vector2i, CellData>` and its `TileMapCell` fields directly, instead of allocating a `TypedArray<Vector2i>` and making three hash lookups for each cell. This reduces temporary allocations and hash probes during rebuilding.
- **Cgame-specific:** set `invalid_cells_cache_dirty = true` on editor layer switch even when the new layer has exactly the same revision as the previous one.
- Use `LocalVector<InvalidCell>` to keep the cached buffer capacity across repeated invalidations instead of a copy-on-write `Vector`.

Retains per-tile deterministic warning colors, fade-in as zoom increases, warning patterns and icons.

## Complexity and memory

| Operation | Before | After |
| --- | --- | --- |
| Full warning eligibility scan | Each overlay redraw, O(number of cells) | When dirty or revised, O(number of cells) |
| Every subsequent redraw | O(all cells) + warning drawing | O(cached invalid cells) + visible warning drawing |
| Temporary buffer for all used cells | Yes, each redraw | None (direct map iteration) |
| Persistent overlay metadata | None | O(invalid cells), plus a revision counter |

The persistent invalid-cell cache uses memory, in exchange for much lower repeated CPU work; it is **not** a universal peak-RAM reduction. It can be worth disabling this strategy for tilemaps where most cells are invalid, but that is not a common authored scene.

Run the deterministic source guards and synthetic baseline:

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_tile_warning_cache.py -v
python3 misc/scripts/bench_tile_warning_cache.py
```

The synthetic Python benchmark verifies the *visible* warnings (not the number of offscreen drawing commands) are identical across simulated viewports and a tile edit. **Its timings are not engine FPS numbers.** A native editor build with `tests=yes` also compiles and runs the C++ `TileMapLayer` revision test.

### Manual acceptance

1. Populate an editor scene with many TileMap cells where only a few point to missing tiles. Pan and zoom across the canvas and verify the visible warnings remain the same.
2. Select a different TileMapLayer containing different invalid tiles with the same initial revision. Verify the old layer's warnings don't persist and the new layer is drawn correctly.
3. Delete or repair a missing tile, change its TileSet resource, and undo/redo; verify the overlay refreshes.
4. Test zoom fade and partially visible edge tiles, including non-square tiles and transformed tilemap layers.
5. Profile GUI CPU time (`TileMapLayerEditor::_draw_overlay`) and memory consumption in a **real** large project. Compare Cgame before/after the commit on identical hardware and scenes.

## Follow-up on earlier CI failures

The same batch fixes two incorrect source-level assertions in `misc/scripts/tests/test_upstream_cold_class_init.py`: they accidentally compared the cold-path mutex/flag to identical syntax appearing earlier in `GDCLASS::get_gdtype_static_mutable`. Now they inspect the body of the cold initialization function. The previous native compile failure in `test_instance_shader_parameters.cpp` has **already been corrected** in `develop` by an independent change adding the missing `ImageTexture` header. No duplicate edit is required.
