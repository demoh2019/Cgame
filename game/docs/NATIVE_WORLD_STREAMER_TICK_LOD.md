# Native cosmetic tick LOD for WorldStreamer

## Motivation

Unreal Engine actors can set a minimum tick interval, reducing the cost of expensive update functions for less significant/distant objects. Cgame already had independent visual residency, opt-in simulation pausing, and a staged world generator, but every still-active `ChunkView` ran its cosmetic `_process` every frame. The new **opt-in native tick interval tier** lets the streamer lower cosmetic update frequency without unloading world assets, disabling collision or changing server/network simulation.

This is inspired by the Unreal Actor TickInterval concept, not a binary-compatible port:
https://dev.epicgames.com/documentation/en-us/unreal-engine/actor-ticking-in-unreal-engine

## Native API

```gdscript
streamer.tick_throttle_radius = 48.0         # -1 (default) disables
streamer.tick_throttle_interval = 0.125     # valid range 0..1 seconds
streamer.tick_throttle_hysteresis = 12.0    # valid range 0..1000 units
streamer.max_tick_throttle_transitions_per_update = 4

print(streamer.get_tick_throttled_count())
print(streamer.is_cell_tick_throttled(Vector3i(1, 0, 0)))
```

**The chunk root must opt in**, implementing `set_streaming_tick_interval(seconds: float)`. The engine only invokes this callback on the main thread; it never blindly disables Node processing or PhysicsServer bodies. A zero interval means full frame-rate cosmetic work. An active far tier uses the configured positive interval; the near tier uses zero. An uninitialized new chunk receives the current interval **before** it enters the scene tree. Later promotions happen closest-first; demotions happen farthest-first, capped at 1..64 transitions per streaming update. Initial per-chunk rates consume the existing generation/adoption budget rather than the transition quota.

The hysteresis band applies to **demotions only**: a near chunk becomes far when its distance exceeds `tick_throttle_radius + tick_throttle_hysteresis`, while a far chunk returns to near when the distance reaches `tick_throttle_radius`. A changed interval propagates to existing far cells under the same transition limit. Turning off the feature (`radius = -1` or `interval = 0`) gradually restores the zero interval to resident roots. Disabled-with-no-active-throttle short-circuits without scanning loaded cells.

Native per-cell bookkeeping is removed on chunk eviction, unload, manual scene teardown, editor reset, and dead object cleanup. Reattaching an explicitly cached procedural scene reapplies the current interval before entering the scene tree; no stale callback state leaks across teleportation. Only chunks with the callback enter the native `get_tick_throttled_count()` count.

## Albion After integration

`ChunkView` now implements `set_streaming_tick_interval`. Its cosmetic `_process` accumulates elapsed seconds and skips grass, decoration scheduling, shadow-caster scans, and windmill rotation when a distant active cell does not yet need an update. When it does, the accumulated delta preserves windmill motion speed and lets the existing time-based grass/shadow checks run normally. The **near zero-interval fast path** is unchanged; independent `set_streaming_simulation_active(false)` still fully stops the cosmetic process.

`GraphicsQuality.apply()` dynamically selects the native tick tier when graphics quality changes:

| Quality | Near full-rate radius | Far update interval |
| --- | ---: | ---: |
| Performance | 32 m | 200 ms |
| Balanced | 48 m | 125 ms |
| High | 64 m | 75 ms |
| Ultra | 80 m | 50 ms |

The separate simulation-pause radius remains 110 m, so chunks outside that radius do no cosmetic updates at all. Native transitions are limited to four per streaming refresh. The game opts in only when the engine actually exposes the API, so older builds remain compatible.

A new `Albion/StreamCosmeticTickThrottled` performance monitor exposes the number of active reduced-frequency scene roots. This is a diagnostic count, **not** a measured FPS gain. Frequency skipping still invokes the lightweight `_process` method to accumulate delta; it skips the costly body work rather than reducing Godot's callback dispatch.

## Verification

Native doctest: `tests/scene/test_world_streamer_tick_interval.cpp`, focused scene test: `game/tests/test_world_streamer_tick_interval.gd`, runner `game/tests/run_streamer_tick_interval.gd`. The focused test checks opt-out, first-adoption callback, bounded prioritized transitions, hysteresis, retuning, disabling/restoring zero rate, cleanup and the real game quality profile. These are added to the established native WorldStreamer CI and full game test list.

To run with the fork binary:

```bash
godot --headless --path game --script res://tests/run_streamer_tick_interval.gd
```
