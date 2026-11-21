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

## Batched per-viewer gather — native engine extension

An optional `query_many(centers: PackedVector2Array, radius: float) -> Array`
on `SpatialRelevancyGrid2D` collects one **source-order-preserving**
`PackedInt64Array` per viewer with a single script/native call. It reuses
the existing exact `query_ids` path for safe cell bounds, inclusive 90 m
distance checks, negative coordinates and oversized radii. Up to 4,096
viewers may be queried in one call; an oversized batch returns an empty
array, allowing game code to fall back rather than silently hide actors.
Empty and invalid individual viewer coordinates behave like scalar calls.

The engine's `get_stats()` now includes `batch_calls` and
`batch_viewers`, in addition to existing per-view query diagnostics.

### Applied to the live Albion After networking path

`GameServer.prepare_snapshot_interest()` now gathers all connected
viewers' 90 m nearby player IDs **and** nearby infected IDs in two
native invocations per 10 Hz network broadcast. Temporary ID lists are
indexed by peer ID in the authoritative server, and
`snapshot_for(peer_id)` consumes those lists while retaining its final
exact-radius and public-field checks. No packet schema or gameplay,
combat or inventory visibility rules were changed.

`finish_snapshot_interest()` clears the temporary caches immediately;
standalone snapshots still use the complete legacy scans. If the native
API is absent (older Cgame binary), a rebuild fails or the batch exceeds
the engine's resource guard, the server retains its existing full-scan
fallback for the whole broadcast.

This adapts the **viewer-dependent gather** stage of Unreal Replication
Graph and Iris prioritization, without claiming full Iris, bandwidth
compression or server-authoritative event dormancy.

References:
- https://dev.epicgames.com/documentation/en-us/unreal-engine/replication-graph-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/iris-prioritization-in-unreal-engine

Native C++ and game integration regressions are in the existing
`test_spatial_relevancy_grid_2d.cpp` and `test_snapshot_interest_grid.gd`
suites; updates to either source file trigger the existing dedicated
`native-spatial-relevancy.yml` CI.
