# cgame_streaming

Native ports of the Cgame open-world streaming and rendering-data libraries that used to live in
GDScript (`game/scripts/shared/*.gd`, `game/scripts/client/virtual_texture.gd`). Semantics match the
GDScript originals; the tests in `tests/` mirror the GDScript test cases.

| Class | GDScript original | Purpose |
| --- | --- | --- |
| `WorldPartitionBake` | `world_partition_bake.gd` | Hierarchical grid bake, data layers, stable GUIDs, HLOD clusters, one-file-per-actor, diff, predictive cell selection |
| `OriginRebasing` | `origin_rebasing.gd` | Floating-origin shifts in grid multiples with exact integer origin |
| `StreamRequestQueue` | `stream_requests.gd` | Prioritised request queue with generations and late-result dropping |
| `StreamReadinessGate` | `stream_readiness.gd` | Data / GPU / physics / navmesh readiness gate, stuck detection, budgeted navmesh warmup |
| `StreamReplication`, `StreamReplicationClient` | `stream_state_replication.gd` | XOR-delta ready-cell bitsets, ack/need_full protocol, anti-cheat |
| `NavMeshStitching` | `navmesh_stitching.gd` | Tile border portals, polygon graph, A* + funnel |
| `NavMeshCarving` | `navmesh_carving.gd` | Obstacle carving with budgeted tile rebuilds (uses `Geometry2D`) |
| `VirtualTexturePageCache` | `virtual_texture.gd` | Sparse virtual texture page table, LRU atlas, indirection image |
| `SHLighting` | `sh_lighting.gd` | L2 SH helpers |
| `ProbeVolume` | `probe_volume.gd` | Adaptive SH probe volume, bake via trace `Callable`, temporal update, streamed cells |
| `VirtualShadowPages` | `virtual_shadow_pages.gd` | Clipmap virtual shadow page allocator |

## Relation to existing modules

* `modules/world_partition` (`WorldPartition3D`) is a scene-instancing streamer for a sparse X/Z grid.
  `WorldPartitionBake` is its offline/data counterpart (bake, diff, HLOD, OFPA) and does not instance
  scenes, so it lives here as a standalone `RefCounted`. The ready-cell queue, readiness gate and
  replication classes are engine-agnostic and can drive `WorldPartition3D` cells (`Vector2i` keys).
* `modules/texture_streaming` (`TextureStreaming`) streams texture mip levels. `VirtualTexturePageCache`
  is a CPU sparse-virtual-texture page cache and does not duplicate it.
* `NavMeshStitching` / `NavMeshCarving` work on 2D polygon tiles with plain `PackedVector2Array`s so the
  results can be fed to `NavigationServer2D`/`NavigationPolygon` by the game. They only depend on
  `Geometry2D`, not on the navigation modules.

## Example

```gdscript
var queue = StreamRequestQueue.new()
queue.max_in_flight = 4
queue.request(Vector2i(3, 4), 10.0, generation)
for cell in queue.next_batch(2):
    load_cell_async(cell)

var gate = StreamReadinessGate.new()
gate.begin(Vector2i(3, 4), Time.get_ticks_msec() / 1000.0)
gate.mark(Vector2i(3, 4), StreamReadinessGate.STAGE_DATA_LOADED)
```

GDScript games should go through `game_facade/cgame_streaming.gd`, which prefers these native classes and
falls back to the original scripts.

## Notes

* Probe volume ray tracing, page providers and navmesh bakes are user callables; they run on the calling thread.
* Cell iteration order follows insertion order (like GDScript dictionaries), so results are reproducible.
* `ProbeVolume.cells_needed` additionally breaks equal-distance ties by cell coordinate (GDScript's
  `sort_custom` is unstable there).
* The shader helper `virtual_texture_sample.gdshaderinc` for the indirection image ships in `game_facade/`.
