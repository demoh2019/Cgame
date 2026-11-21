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

## Immediate camera-turn queue refresh (engine + game)

The customized Godot engine already uses movement and camera hints to prioritize world-chunk generation. However, the original `WorldStreamer` queue was rebuilt at a fixed interval (150 ms in the online game), even after a rapid camera turn. Finished asynchronous scene files also used motion-only priority, unlike procedural chunks.

The engine now optionally refreshes its streaming queue when camera heading changes significantly from the heading **used for the last queue rebuild**, instead of comparing only consecutive frames. It checks the cosine of the turn angle (no expensive `acos`) and refreshes no more often than once every **50 ms**, limiting repeated sorting and scene probing. When it finds a significant turn, it rebuilds the existing candidate set in view-aware order *before* the normal queue drain. The same camera + movement priority is now used to integrate finished asynchronously loaded scenes, rather than only to schedule procedural generation.

New `WorldStreamer.fast_view_refresh_degrees` property defaults to **0** (the old behavior). In Albion After the existing `WorldStreamingPolicy.apply_view()` calls set it automatically for the current quality:

| Graphics profile | Fast turn threshold |
| --- | ---: |
| Performance | 60° |
| Balanced | 45° |
| High | 35° |
| Ultra | 30° |

Lower thresholds improve response to smaller camera cuts; higher thresholds reduce CPU work on slower hardware. No new world cells are added, the loaded set is still bounded by the original player-centered `load_radius` / `unload_radius`, and the existing combined per-frame `max_instantiations_per_frame` / `max_chunk_work_usec` limits are unchanged. A normal camera orbit with no large change continues using the original update interval.

**Testing:** Native C++ `test_open_world.cpp` checks bounded input, no refresh on tiny camera movement, deterministic 90°/180° detection, and an actual streamed procedural queue switching from east to west before its 8-second normal update interval. Godot's `test_world_streamer_shared_budget.gd` verifies per-tier parameters, legacy defaults, camera-policy integration, and runtime property validation. A source-level Python test checks that both finished threaded scenes and procedural queue refresh share the native scheduling policy.

Rebuild the custom Godot engine, then capture a rapid first-person 180° camera turn while standing still and measure queued-cell latency and p95/p99 CPU frame time. Compare High/Ultra against the old 150 ms refresh cadence, and verify no extra chunks or memory growth. This update has not been compiled or profiled on actual hardware in the current session.

## Horizontal camera FOV priority (engine + Albion After)

The streamer now exposes `view_cone_half_angle_degrees` (1–180°, default **180°**).
The old heading-only priority is preserved at the default. When a narrower
value is configured, the native queue still ranks by distance and motion but
smoothly reduces its **cosmetic camera-facing bonus** toward the edge of the
horizontal viewing cone; off-cone chunks receive no view bonus. Both procedural
generation and completed threaded scene activation use the same ranking.

`game/scripts/client/world_streaming_policy.gd` computes a conservative
perspective-camera half-angle from the actual camera FOV, viewport aspect ratio
and `keep_aspect` setting, adding a 12° safety margin. Orthographic cameras,
missing cameras and invalid FOV/viewport dimensions use 180°, which keeps the
old behavior. A feature-detection guard preserves compatibility with older
Cgame binaries without the new property. Existing per-tier view strength and
camera-turn refresh thresholds remain unchanged.

- This is **priority only**, not rendering frustum culling. The load/unload
  radii, cell count, networking, collisions, and server-authoritative gameplay
  are unchanged.
- Native unit tests cover default-equivalent ordering, the reduced priority
  of off-cone diagonals, stable membership, and invalid setter inputs.
- Game tests in `game/tests/test_predictive_streaming.gd` cover the perspective
  aspect-ratio math, fallback behavior and runtime property API.
- Validation on compiled Cgame:
  `godot --headless --path game --script res://tests/run_all.gd`.
  FPS/frame-time claims require a before/after runtime benchmark and are not
  inferred from unit tests alone.

