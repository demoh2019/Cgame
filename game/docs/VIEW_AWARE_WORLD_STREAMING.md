# View-aware world streaming — Cgame native Godot and Albion After

## Purpose

Unreal Engine's **World Partition** prioritizes cells according to streaming
sources, optionally accounting for a source's viewing direction. Albion After
already has a bounded player-centered WorldStreamer with motion lookahead
and a single per-frame generation CPU budget. During idle camera rotation or
photo mode, however, the queue previously used only distance and velocity.

This change adds **camera-facing priority** without expanding the radius,
instantiating any extra nodes, allocating additional GPU buffers, or relaxing
the existing frame-time/instantiation budgets. It aims to reduce visible
terrain/building pop-in during slow turns and photo movement.

References:
- Unreal Engine World Partition and streaming sources:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
- Unreal World Partition HLOD:
  https://dev.epicgames.com/documentation/unreal-engine/world-partition-hierarchical-level-of-detail-in-unreal-engine
- Godot performance profiling:
  https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html

## Native C++ engine implementation

`scene/main/world_streaming_grid.cpp` now exposes
`prioritize_cells_for_motion_and_view(cells, focus, velocity, lookahead,
max_prediction, camera_forward, view_weight, cell_size, axes)`.

- Combines actual distance (65%), bounded motion prediction (35%) and a
  camera-facing bonus in **one stable sort** rather than sorting twice.
- Normalizes camera forward and projects it onto the grid plane. XZ, XY and
  XYZ WorldStreamer axes remain supported.
- Limits the camera bonus to 28% of one cell and 40% of that cell's actual
  distance, scaled by quality strength 0–1. Distant cells cannot displace
  the current player cell.
- Invalid/zero camera vectors, zero quality weight and uninitialized
  view data fall back to existing motion-only priority.
- Cell **membership, residency and eviction are unchanged**. The focus
  cell always wins. All others preserve deterministic coordinate tie
  breakers; no added/freed chunks due solely to a camera rotation.
- `WorldStreamer` exposes validated, normalized, idempotent
  `view_direction` and clamped `view_priority` properties to GDScript.
  These change the sort only on normal streaming updates (0.15 s default),
  not every rendered frame.
- Existing procedural queues are reconciled with the current wanted set
  before scheduling, so camera turns do not accumulate duplicate or stale
  jobs. Threaded scene requests receive the same prioritization.

## Game integration

`world_streaming_policy.gd` now calculates a ground-plane camera heading
from the **actual camera transform after `camera.look_at()`**. The online
world calls `WorldStreamingPolicy.apply_view(streamer, camera,
GraphicsQuality.level())`, including photo/orbit camera behavior.
`velocity_hint` still comes from the player's actual movement and still
uses mounted vs walking prediction. The camera does not change collision,
authority, the network state, fog-of-war, terrain detail presets, or the
resident cell count.

Camera influence is bounded by current visual tier:

| Preset | Camera direction bonus weight | Chunk residency |
| --- | ---: | --- |
| Performance | 0.35 | Unchanged |
| Balanced | 0.48 | Unchanged |
| High | 0.66 | Unchanged |
| Ultra | 0.80 | Unchanged |

Unlike render-resolution scaling this improves **when** assets appear,
not the raw polygon budget or GPU shading cost. It does add a few scalar
operations per queued cell during 0.15-second streaming refresh.

## Validation

`tests/scene/test_open_world.cpp` now checks camera-forward prioritization,
reverse direction, unchanged membership, focus-cell precedence, invalid
inputs, and view-hint clamping. The existing
`game/tests/test_world_streamer_shared_budget.gd` tests policy quality,
real Camera3D headings, camera turns and connection to the live game.

After building the custom engine, run the C++ test target, then:

```sh
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

Visual QA route: stand still near a city chunk border, slowly rotate the
camera while streaming scenery, ride a bicycle at maximum allowed speed,
turn sharply, zoom and enter photo mode, teleport to a remote map cell.
Compare the time to visible scenery at fixed load/unload radii and check
that character collision never appears late within the immediate cell.
Measure p50/p95 frame times, queue depth, generated chunks per frame and
CPU budget use before and after. Focus cell / visible near geometry must
not regress. This change **does not claim an FPS gain without benchmarks**.

Custom engine compilation/runtime is not available in this editing
environment; the new tests must be run on a compiled build.
