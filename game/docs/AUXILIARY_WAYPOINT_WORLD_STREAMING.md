# Bounded auxiliary world streaming source (Cgame / Albion After)

## Why this feature exists

Godot can load scene resources on background threads, while Unreal Engine
World Partition supports runtime streaming sources in addition to the
player's automatic streaming center. Albion After already uses Cgame's
native `WorldStreamer` for procedural chunks with separate CPU and
resource budgets. The game also has a player-owned private map waypoint
and a map of expedition objectives.

Before this feature, choosing a waypoint on the map had no effect on
chunk loading. The source radius always followed only the player. When
approaching a marked outpost or landmark, scenery near the destination
could appear late after movement or camera priority had selected other
chunks.

## New public engine capability

Cgame now exposes methods on `WorldStreamer`:

```gdscript
streamer.set_auxiliary_source(Vector3(140, 0, 200), 32.0)
print(streamer.has_auxiliary_source())
print(streamer.get_auxiliary_source_position())
print(streamer.get_auxiliary_source_radius())
streamer.clear_auxiliary_source()
```

The auxiliary source is a *secondary scene-streaming hint*, not another
player or server-owned world authority. It is supported by the same
procedural-generator and threaded-resource paths as normal chunks.

### Hard safety and memory limits

1. The source radius cannot exceed **two chunk widths**, even if the
   caller passes a much larger value.
2. A source whose center is farther than **`load_radius + cell_size`**
   from the primary streaming focus is dormant. A map pin hundreds of
   metres away is stored but creates no remote world.
3. The primary focus's existing set of cells is protected: the source
   only adds a few unique nearby cells within `MAX_CELLS`, and a source
   is disabled if the primary wanted set already fills that bound.
4. Extra cells are interleaved at **one per three primary cells**, with
   the primary focus cell always taking first place. A single source
   cannot starve player-centered loading.
5. Both paths use the **same** `max_instantiations_per_frame` limit and
   `max_chunk_work_usec` time slice. There are no background GDScript
   scene mutations or additional physics callbacks.
6. Extra cells are unloaded after clearing the source when they fall
   outside the regular focus's unload radius. Cells still wanted by
   the primary focus are never forcibly unloaded.

## Albion After integration

`WorldStreamingPolicy.apply_waypoint` reads the personal map waypoint
during `online_main.gd` world updates, after the current server-corrected
display position has been applied as `WorldStreamer.focus_position`.

- No waypoint / cleared waypoint / invalid network position: disable
  the extra source.
- Distant map pin or expedition objective: **no extra streaming**.
- Pin within the player radius plus one cell width: prefetch up to
  **1.5 cells** around the destination while walking or **2 cells**
  while riding. The game chooses these *bounded* radii; the engine has
  an independent upper bound.
- Mount/dismount and changing/clearing the pin update the source
  without resetting the primary loaded world.
- The source uses the XZ ground grid and ignores the player's Y
  changes, preventing per-frame rescheduling on hills.

This is purely client-side presentation/prefetch behavior. The waypoint
is already private and never sent as a new RPC; quest markers and combat
remain fully server-authoritative.

## Route-aware chunk priority and local detours (2026-11)

The active **Albion After** client now connects its private waypoint to a
second, complementary Cgame feature: native
`WorldStreamer.set_route_cells(Array[Vector3i])`.

The game uses Godot's built-in `AStarGrid2D` to calculate a short, strictly
four-neighbor sequence of XZ chunks between the player's current cell and a
nearby map waypoint. If gameplay supplies blocked local cells, the route
detours within a three-cell margin around the direct corridor. A plan is
rejected if it is longer than 64 cells, unreachable, out of range or has
an invalid endpoint; a distant map marker still cannot activate routing.
The policy caches unchanged endpoints, avoiding AStar recalculation every
render frame when a player stands in the same chunk.

```gdscript
var route: Array[Vector3i] = WorldStreamingPolicy.plan_waypoint_route(
    streamer, personal_waypoint, player_position,
    [Vector3i(1, 0, 0)] # Optional local blocker supplied by gameplay.
)
streamer.set_route_cells(route) # Or leave integration to apply_waypoint().
```

On every normal queue rebuild, native WorldStreamer takes the game-planned
route and **reorders only already eligible player-radius chunks**.
The player's own chunk stays first; between prioritized route chunks,
up to two normal nearby chunks are scheduled. The existing procedural
generator and threaded scene-loader integration counts and 2.5 ms soft
time slice are shared without modification. The usual auxiliary source
is unchanged and can still add a small capped nearby waypoint island.

This is a **streaming priority corridor**, not a physical NPC pathfinding
system, server-authoritative movement, navigation mesh generator or
unbounded route residency lease. The game currently supplies its
*private waypoint* as the route destination. Dynamic blockers are an
optional game API intended for future hazard/quest integration; the
ordinary online client does not yet populate blocker cells. Because
the route is only a priority hint, it cannot block or open navigation
links or directly move characters.

`clear_route_cells()` explicitly resets the scheduling hint. Invalid
external paths are rejected by the native engine: no duplicate,
diagonal, teleported, off-plane or longer-than-64-cell route can be
installed. The method is idempotent on repeated equal inputs.
`get_route_cells()` reports the current hint for diagnostics.

## Test plan

```sh
# Cgame custom editor with WorldStreamer:
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
```

`game/tests/test_waypoint_streaming_source.gd` uses a real native
WorldStreamer and a deterministic procedural chunk callback, testing
primary focus priority, actual auxiliary chunk adoption, post-clear
unloading, bounded memory radius, remote-target rejection, shared
generation budget, pedestrian/riding policy, malformed map pins and
live-game wiring, plus AStar detours, native route-path validation,
per-refresh budget guarantees, focus-first priority and remote-cell exclusion.
The dedicated Cgame CI workflow compiles the engine
and runs the headless graphics suite.

No measured loading-time or FPS improvement is claimed until a native
build and a repeatable mounted traversal benchmark have completed.

## Comparison references

- [Unreal Engine World Partition streaming sources](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine)
- [Godot background resource loading](https://docs.godotengine.org/en/stable/tutorials/io/background_loading.html)
