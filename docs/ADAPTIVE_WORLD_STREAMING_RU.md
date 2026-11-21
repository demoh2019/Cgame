# Adaptive WorldStreamer CPU Backpressure

A native, opt-in slow-frame pressure controller for the Godot `WorldStreamer`
class, integrated with the **real Albion After procedural world**.

It uses the previous render frame's duration to adapt both the amount of
main-thread chunk work permitted and the maximum number of chunk integrations
per frame. It does not change queued-cell priorities, load/unload radii,
async ResourceLoader threads, terrain generation, or authoritative gameplay.

## Configuration in Albion After

```gdscript
streamer.max_instantiations_per_frame = 3
streamer.max_chunk_work_usec = 2500
if "adaptive_chunk_budget_enabled" in streamer:
    streamer.adaptive_chunk_budget_enabled = true
```

Backpressure rises by 0.16 per frame slower than 30 ms, recovers by 0.05 per
frame faster than 20 ms, and holds in between. Disabled by default in Godot
for existing game compatibility.

| Streaming pressure | Integrations / render frame | Main-thread soft deadline |
| :--- | ---: | ---: |
| Below 40% | 3 | 2,500 µs |
| 40–79% | 2 | 1,875 µs |
| 80–100% | 1 | 1,250 µs |

This is *soft* scheduling: a single chunk remains indivisible and may exceed
the deadline. At least one chunk remains permitted per streaming frame, so
slow-frame backpressure cannot permanently starve loading by reducing all
slots to zero. The previous async prefetch and motion/view priority remain.

## Engine diagnostics

The engine exposes measured **main-thread** time, including procedural
generator calls, Node adoption/ready callbacks, and ready-scene finalization.
Threaded resource decoding is not included.

- `get_last_frame_chunk_work_usec()` — the previous completed stream frame.
- `get_last_frame_chunk_attempt_count()` — attempted integrations, including
  missing or failed procedural results.
- `get_streaming_frame_pressure_percent()` — current pressure 0–100%.
- `get_effective_instantiations_per_frame()` — active count limit.
- `get_effective_chunk_work_usec()` — active soft wall-clock cap.

These appear as five read-only monitors in Godot's Debugger → Monitors under
the `Albion/` namespace. They are removed when the client scene exits.

## Tests

Native: `tests/scene/test_world_streamer_backpressure.cpp`.

GDScript: `game/tests/test_world_streamer_backpressure.gd`, including a
detached real procedural chunk refresh and legacy compatibility checks.

Python contracts: `tests/scene/test_world_streamer_backpressure_contract.py`.

Workflow: `.github/workflows/native-world-streamer-backpressure.yml` builds
the custom Godot editor and runs C++ and headless game tests.

**No measured performance improvement is asserted before a real native
Godot build and FPS/frametime benchmark pass.**
