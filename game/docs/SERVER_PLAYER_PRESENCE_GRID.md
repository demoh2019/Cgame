# Server Player Presence Spatial Grid

This reusable GDScript **engine service is integrated into the actual game**:
`game/scripts/server/player_presence_grid.gd` builds a lightweight, CPU-side
spatial index of living survivors' authoritative XZ positions. The canonical
`GameServer._manage_zombie_population()` rebuilds it once each population
maintenance pass (normally every 20 ticks, approximately once per second).

## Why

Previously, infected spawn suppression and distant-infected unloading each
called `_nearest_player_distance()`, scanning every survivor for every
procedural spawn candidate and every active infected. This incurred a
repeated O((spawns + infected) × players) search at large player counts.

The index uses fixed 64 m grid buckets with `Vector2i` keys and tests only
buckets overlapping a query's bounding square. Distances within those
buckets use **exact squared XZ distances**, retaining the original circular
radii and side-of-boundary behavior.

For solo and small co-op sessions (**8 or fewer** survivors), the engine
uses a direct scan without allocating grid buckets. For larger groups, the
bucket index is used automatically. A query with a radius **above 512 m**
also falls back to an exact direct scan, avoiding an unbounded grid walk.

## Existing gameplay behavior preserved

- Procedural infected **do not appear strictly inside 12 m** of a living
  player. At exactly 12 m, the legacy rule permits the spawn.
- Non-protected infected are unloaded **only if farther than 130 m** from
  every living player. At precisely 130 m they are retained.
- Cache guards and active night-horde participants continue to use their
  existing protection rules and do not get forcibly unloaded.
- Empty player sets unload unprotected infected, as before.
- The grid is rebuilt from current server positions each pass, so teleports,
  deaths, disconnects and active-player changes do not leave stale entries.
- No client-controlled positions, RPCs, persistence or network payloads
  were added. The rest of `GameServer` stays server-authoritative.
- Other uses of `_nearest_player_distance()` (e.g. raid lifetime checks)
  remain intact and are not silently changed.

## Runtime diagnostics

The existing ten-second dedicated server log now includes three additional
fields (illustrative, **not measured benchmark data**):

```text
SERVER players=24 zombies=110 ... presence_queries=180 presence_candidates=55 presence_buckets=410
```

These report the latest completed population-maintenance pass, not a
cumulative total. `presence_candidates` counts candidate player positions
actually compared against a distance query. `presence_buckets` counts
grid-cell lookups. For up to 8 players, `presence_buckets` remains zero.

This change reduces the *search space* for widely distributed groups; actual
CPU improvement depends on player density, the number of population
candidates and hardware. Broadphase bucket lookups may be more expensive for
closely packed groups, which is why small groups use the direct path.
No FPS or measured speedup is claimed without hardware benchmarks.

## Tests

Run the canonical Godot suite:

```bash
godot --headless --path game --script res://tests/run_all.gd
```

`res://tests/test_player_presence_grid.gd` tests:
negative coordinates, zero and exact-distance boundaries, inclusive versus
strict radii, invalid coordinates, direct and hashed modes, randomized
comparison against a brute-force reference, defensive diagnostics,
and a `GameServer._manage_zombie_population()` integration fixture with
near/far infected and a teleported player.

**Runtime caveat:** Godot is not installed in the authoring environment.
Tests are registered but cannot be honestly reported as passing until a
real headless Godot execution finishes.

The design follows general spatial partitioning and entity-processing
approaches used in large-scale game engines. It is not a replacement for
Godot's PhysicsServer, Unreal Mass Entity or Unity DOTS.

References:
- https://docs.godotengine.org/en/4.6/tutorials/performance/cpu_optimization.html
- https://dev.epicgames.com/documentation/unreal-engine/overview-of-mass-gameplay-in-unreal-engine
