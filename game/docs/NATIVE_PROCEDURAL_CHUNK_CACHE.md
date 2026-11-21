# Bounded procedural chunk reuse for WorldStreamer

## Why

WorldStreamer already supports World Partition-style streaming sources, directional priority, per-frame instantiation limits, an independent simulation tier, and asynchronous resource loading. **Procedural generator** worlds still paid the complete terrain, scenery and MultiMesh construction cost when the player oscillated across an unloading boundary and quickly returned to the same cell. Unreal Engine's open-world streaming concepts motivated a small **opt-in, detached scene-root cache** (not an Unreal API clone).

## Native API

```gdscript
streamer.set_chunk_generator(_make_chunk)
streamer.max_cached_chunks = 2  # default 0; hard cap 16.
print(streamer.get_cached_chunk_count())
print(streamer.get_chunk_cache_hit_count())
print(streamer.get_chunk_cache_eviction_count())
streamer.clear_cached_chunks() # Releases detached resources and resets counters.
```

To allow scene reuse, the generator's **root** must return `true` from `can_cache_streaming_chunk() -> bool`; without that explicit permission the streamer always uses legacy free-on-unload. It is restricted to procedural chunk generators; ordinary PackedScene/threaded loads are never cached. Only the same **exact cell** can reattach an evicted/detached root.

When a cacheable chunk is unloaded, it is detached from its parent (no world residency, visibility, `_process`, or physics) and added to a strictly bounded oldest-first cache. If the current focus or auxiliary source requests a cached cell again, eviction protects that cell ahead of nonrequested older chunks, so even a one-chunk cache helps with immediate backtracking. Reattachment goes through the ordinary `_adopt_chunk` route: the root gets the current simulation LOD, optional staged-visual diagnostics, the `chunk_loaded` signal and any newly configured scene parent. After reattachment, an optional `on_streaming_cache_restored()` hook can reinstate deferred cosmetic services. **Godot does not rerun `_ready()` for already initialized nodes**, so the hook must refresh state that depends on the observer/camera.

Every hit **still consumes a normal chunk-instantiation slot and main-thread work budget** (reattaching a subtree may itself be expensive). Cache misses invoke the unchanged generator path. Cache eviction and `clear_cached_chunks()` free detached resources. Grid/cell-size changes, chunk-generator changes, chunk-parent changes, streamer teardown, and `unload_all()` invalidate/release retained nodes. Disabled mode is functionally identical to previous behavior.

This trades **retained GPU/CPU memory** (up to 16 complete chunk roots) for avoided reconstruction on near-term revisits. The node count is bounded, not the total bytes; choose small caps or disable on low-memory devices. Only opt in immutable or explicitly cache-safe visuals. Do **not** cache authoritative NPCs, active physics, transient loot, network state, multiplayer entity ownership, or chunks whose content can change while absent.

## Albion After

`game/scripts/client/online_main.gd` enables a **1 or 2 chunk** cache according to the existing quality preset. `ChunkView` opts in because its terrain, vegetation, static decorations and generated scenery are client-side, seeded visuals; server-authoritative gameplay remains in its separate world/entity simulation. On return, it refreshes grass LOD and shadow checks, restores unfinished decoration scheduling if needed, and honors the current independent simulation tier.

Game performance telemetry includes:
- `Albion/StreamCacheRetained`
- `Albion/StreamCacheHits`
- `Albion/StreamCacheEvictions`

These are counts, **not** measured CPU savings. Validate real-frame time and memory usage on target devices before increasing the cap.

## Verification

`game/tests/test_world_streamer_chunk_cache.gd` checks opt-out behavior, identity-preserving reuse, generation-call avoidance, residency and simulation separation, LRU eviction, invalidation, unsafe roots and the Albion After restoration callback.

```bash
godot --headless --path game --script res://tests/run_chunk_cache.gd
```

`tests/scene/test_world_streamer_chunk_cache.cpp` verifies native defaults, hard cap and reset. Native WorldStreamer CI runs both suites and the existing streaming regressions.

Unreal open-world streaming reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
