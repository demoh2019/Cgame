# Broadcast-scoped building relevancy and actionable siege alerts

The dedicated server sends each survivor a private snapshot of their own
status and a public list of nearby walls/house pieces. Previously, the same
full wall set was scanned **once per receiver** to build that visible list
and derive private upkeep/attack alerts. In a large settlement this repeated
work even when all viewers shared the same authoritative tick.

## Building snapshot batch

At the start of the already-established network broadcast lifecycle,
`GameServer.prepare_snapshot_interest()` now builds exactly one
`BarricadeSnapshotIndex`:

- A 64-metre grid of wall *centres*. Radius filtering uses the same exact
  squared-distance rule as the previous authoritative scan and preserves
  the original wall insertion order.
- Private, already-aggregated owner summaries keyed by authenticated account
  and guest peer IDs. Owners with both account and legacy guest walls get both
  sets without exposing another owner's data.
- Cached state is used only during a matching server tick, structure revision
  and wall count. Direct snapshots, unsupported engine builds and stale
  broadcast caches rebuild from live authoritative state rather than dropping
  walls or alerts.
- `finish_snapshot_interest()` drops the temporary grid and owner maps.
  `last_snapshot_wall_stats` reports wall count, occupied cells and the
  number of snapshot recipients that reused the cached index.

No new engine classes, persistent world data or client RPC methods are
required. The existing client understands the unchanged public wall payload.

## Where is my base being attacked?

The current `BASE UNDER ATTACK` warning is extended with the **distance
and compass direction** to the *most recently attacked owned structure*.
The server chooses the newest unexpired infected-hit event, even for a
distant base. Clients derive bearing using the existing north-up navigation
utility. Expired attacks and clients connected to older servers display no
false marker.

The private `you.base_upkeep` summary only includes `attack_x` and
`attack_z` when an owned structure has an active infected attack. Other
accounts receive neither the event location nor the owner's aggregate
warning. This does not expose attacker identities, invent damage, alter
wall durability or unlock remote interactions.

## Regression coverage

`test_snapshot_interest_grid.gd` now compares 90 seeded broadphase
queries against the original exhaustive pass across 220 walls, checks
exact radius/order, wide-radius fallback, invalid query inputs, private
account/guest summaries, newest attack location, expiry, the real server
broadcast lifecycle and stale-cache invalidation after live wall damage.

```sh
bin/godot.macos.editor.arm64 --headless --path game --script res://tests/run_one.gd -- test_snapshot_interest_grid
```
