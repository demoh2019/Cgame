# Building upkeep optimization and owner alerts

Albion After's existing barricades, reinforced structures, house pieces and
doors all use the same server-authoritative upkeep rules. A survivor must
visit their own structure within 15 metres to renew the six-hour upkeep
period. Unattended structures gradually lose HP and eventually collapse.

## Performance

Previously, every upkeep pass compared every wall with **every** connected
survivor. With hundreds of structures, this was an expensive product of
player and wall counts, even though only the legitimate owner could renew
each wall.

Now a single per-pass `WallUpkeepIndex.live_owners()` groups **living**
survivor positions by authenticated account (or guest network peer). Each
wall tests only positions belonging to its valid owner, using squared
2D distances with the original inclusive 15-metre boundary.

The index is temporary and never persists account IDs or shares them over
the network. Account-owned structures can be renewed after reconnect,
whereas guest walls remain bound to their original peer. Building decay,
resource costs, repair permissions and server persistence are unchanged.

## Owner-only HUD warnings

The existing per-survivor world snapshot already scans all walls to send
nearby public building geometry. That pass now also counts **only the
viewer's own** walls needing attention, even when their base is distant.

- **BASE UPKEEP** warns when one or more owned structures have at most
  one hour of upkeep left (or are already decaying), showing the number
  and shortest remaining time in minutes.
- **BASE DEFENSE** warns when one or more owned walls are below 50%
  durability, so the owner can plan repairs before a raid.

Only the authenticated owner's private `you.base_upkeep` field contains
these counts and timer. Public building snapshots still contain no
account IDs or upkeep timestamps. The HUD accepts snapshots from older
servers that do not provide this field.

No new RPCs, saves, persistent player fields or world seeds were added.

## Regression

`game/tests/test_wall_upkeep.gd` covers unauthorized players standing by
a base, guest/registered ownership, account reconnect, exact-distance
renewals, expired-wall decay, warning thresholds and owner-only information.

```sh
bin/godot.macos.editor.arm64 --headless --path game --script res://tests/run_one.gd -- test_wall_upkeep
```
