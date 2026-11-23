# World chunk LRU and collision broadphase

Albion After shares seeded `WorldGen` across the dedicated server and client
prediction. Players should not experience a burst of regenerations when the
256-cell chunk cache fills. This optimization does not change chunk content,
world seeds, spawn IDs, depletion, or the save format.

## Chunk residency

- Every cache hit updates one monotonic usage counter in O(1).
- A cache miss generates one chunk. Only when all 256 entries are occupied
  does it evict the **least recently used** chunk, rather than clearing the
  entire map and forcing the next 256 lookups to regenerate.
- Eviction is O(256) *on a miss at capacity*, not on the normal query path.
- The auxiliary solid-collision index is evicted along with its chunk, so
  stale geometry never lingers after leaving a region.

## Collision query

When a chunk is first generated, one per-chunk index records only objects
with `blocks = true`, in exactly the old order: `nodes`, `crates`,
`structures`, and `props`. `blockers_near()` tests this smaller list
instead of walking all decorative objects every time. This improves
server movement, structure placement, respawn selection, and local
client collision prediction.

The index does not cache depleted state. A mined stone stops blocking
immediately; a respawned stone blocks again. Player-built obstacles use the
existing mutable dynamic-blocker collection and remain authoritative without
waiting for chunk regeneration. Dungeon and hub collisions are unchanged.

## In-game live diagnostics

Use **Ctrl+Shift+F3** to open the performance panel and
**Ctrl+Shift+F4** to cycle modes. Three new numeric monitors are shown:

- `cache_cells`: number of cached procedural chunks (maximum 256).
- `cache_evicted`: cumulative count of individual LRU evictions.
- `cache_hit_pct`: percent of chunk lookups served from memory.

The counters are constant-time to read; profiling does not regenerate chunks.
The public helper `WorldGen.chunk_cache_stats()` also returns hits, misses,
capacity, residency, eviction count, and collision-index residency.

Focused regression: `res://tests/test_world_gen.gd` checks bounded residency,
survival of hot chunks, eviction of cold chunks, exact original collision order,
resource depletion, and dynamic structures.

```sh
bin/godot.macos.editor.arm64 --headless --path game --script res://tests/run_one.gd -- test_world_gen
```
