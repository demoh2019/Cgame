# territory_control.gd

> Session-based PvP outpost control, a precursor to persistent clan sieges.

`res://scripts/shared/territory_control.gd`

## Overview

Session-based PvP outpost control, a precursor to persistent clan sieges.
All presence, group ownership and stamina support are derived from the
authoritative world simulation. Clients can observe but never set ownership.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const OutpostFortification = preload("res://scripts/shared/outpost_fortification.gd")`
- `const OutpostWatch = preload("res://scripts/shared/outpost_watch.gd")`
- `const OutpostBreach = preload("res://scripts/shared/outpost_breach.gd")`
- `const OutpostSupplies = preload("res://scripts/shared/outpost_supplies.gd")`
- `const OutpostProvisions = preload("res://scripts/shared/outpost_provisions.gd")`
- `const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")`
- `const MAX_SITES := 3`
- `const CAPTURE_RADIUS := 12.0`
- `const RALLY_RADIUS := 18.0`
- `const HARVEST_RADIUS := 100.0 # Economic benefit is local to a captured outpost.`
- `const FIELD_BENCH_RADIUS := 6.5 # Owner-only portable bench at the central flag.`
- `const CAPTURE_SECONDS := 30.0`
- `const HOLD_SECONDS := 900.0`
- `const MIN_CAPTURERS := 2`
- `const RALLY_STAMINA_PER_SECOND := 2.0`

## Functions

### `persistent_holds`

```gdscript
func persistent_holds(now: float) -> Array
```

The guild holds that must survive a restart: [{id, guild, name, remaining}] (remaining in seconds of the hold).

### `restore_holds`

```gdscript
func restore_holds(holds: Array, now: float) -> void
```

Restores validated holds after a restart: each site is held by its guild, unmanned, for the time that was left.

### `public_state`

```gdscript
func public_state(now: float, players: Dictionary = {}, parties = null) -> Array
```

### `capture_target`

```gdscript
func capture_target(site: Dictionary) -> float
```

A fortified owner's flag requires more uninterrupted enemy presence.
Neutral and newly captured sites always use the base capture duration.

### `watch_recipient`

```gdscript
func watch_recipient(peer_id: int, site_id: int, event_owner: int, players: Dictionary, parties, now: float) -> bool
```

Remote alarm delivery is limited to the current owner party and
backend-verified members of its homogeneous guild banner.
Previously queued events for a lost/captured flag cannot leak to a new owner.

### `site_by_id`

```gdscript
func site_by_id(site_id: int) -> Dictionary
```

### `contested_by_rivals`

```gdscript
func contested_by_rivals(site: Dictionary, group_id: int, players: Dictionary, parties) -> bool
```

### `tick`

```gdscript
func tick(delta: float, now: float, players: Dictionary, parties) -> Array
```

### `claim_supplies`

```gdscript
func claim_supplies(site_id: int, player, players: Dictionary, parties, world, now: float) -> Dictionary
```

Server-only lookup that rechecks live occupancy rather than stale snapshot
contested state. A hostile player physically present blocks supply claims.

### `deliver_provisions`

```gdscript
func deliver_provisions(site_id: int, player, players: Dictionary, parties, now: float) -> Dictionary
```

Live server party, guild and rival presence checks at delivery time.

### `has_rally_bonus`

```gdscript
func has_rally_bonus(peer_id: int, position: Vector3, parties, now: float, players: Dictionary = {}) -> bool
```

### `harvest_bonus`

```gdscript
func harvest_bonus(peer_id: int, node: Dictionary, players: Dictionary, parties, now: float, world) -> int
```

Holding a dangerous-zone outpost rewards nearby harvesters, not remote farmers.
All ownership, Nakama clan membership and live contesting sides are resolved
on the server at harvest completion, so losing a flag cancels the benefit.
The reward is exactly one additional raw crafting resource per node.

### `has_field_workbench`

```gdscript
func has_field_workbench(peer_id: int, players: Dictionary, parties, now: float) -> bool
```

Captured outposts act as local workbenches for their occupying party or a
fully verified owning guild. The authoritative server checks current world
position, expiry and *live* rival occupancy immediately before crafting.
An old client snapshot or stale contested flag never opens a station.

_3 private function(s) starting with `_` are not listed._
