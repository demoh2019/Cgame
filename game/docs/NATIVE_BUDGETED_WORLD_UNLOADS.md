# Native WorldStreamer bounded chunk unload scheduling

The current Cgame/Albion After `WorldStreamer` already limits main-thread generation, native scene adoption, and simulation-tier transitions. It previously **removed every distant procedural chunk in one streaming refresh** (including post-teleport), potentially producing a frame spike. This feature adds a configurable bound on removals, inspired by Unreal Engine World Partition's runtime distance-based cell streaming; it does **not** imply Unreal exposes this exact setting.

## Engine API

```gdscript
streamer.max_unloads_per_update = 20 # Opt-in. Default 0 = existing unlimited behavior.
print(streamer.get_last_unload_count())
print(streamer.get_last_deferred_unload_count())
```

The setter clamps integers to **0–64**, is idempotent, and triggers a new scheduler pass only when changed. The main focus still chooses residency using the existing `max(load_radius, unload_radius)`; nearby auxiliary sources retain their cells. Each refresh enumerates out-of-range candidates, then retires at most the configured limit, **farthest first** (lexicographic ties), under bounded O(stale-cells × budget) selection work with no full sort. Zero removes all candidates in one pass as before. Deferred cells remain loaded until the next streaming refresh, and any return journey re-evaluates the residency and **cancels stale removals**. No persistent deletion queue is maintained.

`get_last_unload_count()` and `get_last_deferred_unload_count()` report actual work and remaining eligible removals **from the most recent refresh**, not constant-time estimates of current player position. Manual `unload_all()`, grid resets and teardown remain immediate for safety, independent of the limit. The configured setting never changes the generator's CPU/frame slot budgets, retry/failed/missing semantics, the visual-detail completion callback, the opt-in procedural scene cache or network/server authoritative state.

**Tradeoff:** deferring scene removal retains CPU/GPU memory and temporarily resident nodes. Do not enable it for authoritative streamed physics or gameplay-critical simulation without an explicit lifecycle strategy. On very long teleports the old visuals may persist for multiple refreshes; tune the cap and radius using profiler traces rather than claiming an unmeasured FPS win.

## Albion After

`GraphicsQuality.apply()` updates the active visual-streamer budget whenever graphics quality changes, using `GraphicsQuality.unload_budget_for_quality()`:

| Graphics tier | Max retired chunks / update |
| --- | ---: |
| Performance | 12 |
| Balanced | 20 |
| High | 32 |
| Ultra | 48 |

The main world uses client-generated `ChunkView` scenery only. The current graphics quality is already reapplied after the main `WorldStreamer` has been constructed; no additional scene ownership or renderer paths are needed. The game detects the optional new engine API, so older Cgame binaries retain the legacy unlimited behavior.

The performance panel tracks `Albion/StreamUnloadedLastUpdate` and `Albion/StreamUnloadsDeferred` through native read-only counters. Their reported counts, not measured frame-time changes, are the accepted output until device-specific performance testing is available.

## Regression coverage

- Native C++ doctest: `tests/scene/test_world_streamer_unload_budget.cpp` for default/clamp/cleanup.
- Real-GDScript integration: `game/tests/test_world_streamer_unload_budget.gd` covers original behavior, strict per-refresh cap, farthest-first priority, instant focus reversal, eventual draining, manual cleanup bypass, auxiliary-source residency, and graphics-profile integration.
- Focused runner: `godot --headless --path game --script res://tests/run_streamer_unloads.gd`.
- Added to the existing native-streamer CI and full Albion game test inventory.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
