# Native Spatial Relevancy Grid — network interest management

Inspired by Unreal Engine's **Replication Graph** and actor relevancy,
the custom Cgame engine provides reusable `SpatialRelevancyGrid2D`
(`scene/main/spatial_relevancy_grid_2d.{h,cpp}`) to build lists of
nearby entity IDs for many simultaneous viewers without walking every
entity for every recipient.

## Public engine API

- `rebuild(ids: PackedInt64Array, positions: PackedVector2Array) -> bool`:
  validates matching, unique IDs, finite coordinates and a 65,536-entry
  upper bound, then builds 64 m cell buckets.
- `query_ids(viewer: Vector2, radius: float) -> PackedInt64Array`:
  returns IDs inside the exact inclusive circle **in source input order**.
- `set_cell_size`, `set_max_indexed_radius`, `clear`, `get_stats`:
  manage configuration, reset indices and inspect per-viewer lookup costs.
- Small crowds (<=8 actors), very large radii (>2048 m), or unsafe
  32-bit cell coordinates use the exact direct scan instead of creating
  massive bucket walks or overflowing coordinates. Bad inputs fail the
  entire rebuild and let the caller keep its original safe scan.

The grid stores **IDs and positions only**. It does not send RPCs, retain
Node references or grant actor/network authority, and is useful to any
Cgame project for AI visibility, snapshot relevancy or interest queries.

## Live Albion After integration

`GameServer.prepare_snapshot_interest()` builds separate player and living
infected indices just once per synchronous 10Hz snapshot broadcast.
`snapshot_for(peer_id)` queries them for 90m nearby players and living
infected, preserving dictionary insertion order, existing exact radius
checks and all public information policies. Other snapshot categories
(loot, hazards, structures, boss warnings, private inventory and abilities)
continue following their existing independent authorization rules.

`Net.server_tick()` surrounds all per-peer snapshots with
`prepare_snapshot_interest()` / `finish_snapshot_interest()`.
Outside this window, `snapshot_for` uses its original direct scans,
so independent tests, admin/script calls and relocation between broadcasts
cannot consume stale indices. Failed native builds or stock Godot keep
the legacy fallback and never silently hide relevant entities.

Diagnostics `last_snapshot_interest_stats` report whether the native
path was enabled and aggregate grid queries, candidates and cells.
This is a **CPU relevancy accelerator**, not bandwidth compression,
not a new replication protocol, and not a replacement for Unreal Iris.

## Tests / verification

The dedicated `.github/workflows/native-spatial-relevancy.yml`
compiles Cgame with doctest, runs native spatial query tests and
imports/tests the canonical `game/` project.
`game/tests/test_snapshot_interest_grid.gd` covers native query
boundaries, validation, source ordering, exact payload parity,
teleports and the Net snapshot lifecycle.

No measured performance speedup is asserted until successful native
build and benchmark results.

References:
- https://dev.epicgames.com/documentation/en-us/unreal-engine/replication-graph-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/actor-relevancy-in-unreal-engine
