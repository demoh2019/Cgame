# Native budgeted streaming simulation tiers

Cgame's `WorldStreamer` now has an opt-in **independent simulation tier**, inspired by Unreal Engine World Partition's separation of loaded content from runtime activation and its performance-oriented distance policies.

In Albion After, visual chunks remain resident between the normal `load_radius = 150` m and `unload_radius = 220` m. The separate `simulation_radius = 110` m, 20 m hysteresis, and at most four simulation transitions per streaming update pause **only** optional per-chunk cosmetic CPU work on distant `ChunkView` roots. No server entity, loot, collision, terrain mesh, audio, authoritative combat or scene residency state is altered.

## Engine API

```gdscript
streamer.simulation_radius = 110.0 # -1 (default) keeps all loaded chunks active.
streamer.simulation_hysteresis = 20.0
streamer.max_simulation_transitions_per_update = 4

if streamer.is_cell_simulation_active(Vector3i(1, 0, 1)):
    pass
print(streamer.get_simulation_active_count())
```

Any chunk scene root **may** opt in with `set_streaming_simulation_active(active: bool)`. The engine never changes arbitrary child process modes, physics layers, or gameplay state. New scene roots get their initial tier before entering the scene tree; transitions of existing roots are capped and choose near-field activations first. Active chunks remain active until leaving the outer (radius + hysteresis) band; inactive chunks only resume inside the inner radius.

When the radius is negative (default), no callbacks are made for newly loaded chunks. Disabling an active tier restores paused roots under the same transition budget. Unloading forgets all state. `chunk_simulation_changed(cell, active)` and `get_simulation_active_count()` support diagnostics.

## Albion After opt-in

`game/scripts/client/online_main.gd` enables the feature when running on a Cgame build that exposes it, and registers `Albion/StreamSimulationActive` as a performance monitor. `ChunkView.set_streaming_simulation_active()` pauses/resumes its `_process` loop, which services staged scenery, grass LOD, shadow updates, and windmill sail animation. Grass gets an immediate recheck on reactivation. The terrain node, collisions, and other unrelated scripts continue unchanged.

## Verification

- `game/tests/test_world_streamer_simulation_tiers.gd` checks legacy behavior, bounded transition counts, preserved residency, hysteresis, restoration, initial tier setup, callback idempotence, and cleanup.
- Run the native-engine game test suite with `godot --headless --path game --script res://tests/run_all.gd` using the **Cgame binary**, not an unmodified Godot release.
- No measured FPS uplift is claimed until testing on a representative open-world traversal and hardware profile.

Reference: [Unreal World Partition](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine).
