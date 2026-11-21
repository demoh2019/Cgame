# world_sharding.gd

> World sharding planner: grid regions -> zone servers, load rebalancing with hysteresis, ghost (interest) replication near borders and an idempotent two-step ...

`res://scripts/server/world_sharding.gd`

## Overview

```text
World sharding planner: grid regions -> zone servers, load rebalancing with hysteresis,
ghost (interest) replication near borders and an idempotent two-step player handoff.

Original GDScript implementation. Design references (concepts only, no code copied):
  - SpatialOS workers/entity authority & ghost "checkout" model (Improbable docs).
  - EVE Online node-per-solar-system model and Albion Online zone servers.
  - Greedy longest-processing-time (LPT) scheduling for balanced assignment.
No third-party code included.
```

## Documented variables

- `var border_margin: float = 15.0` - ghost replication distance to neighbour regions
- `var handoff_hysteresis: float = 3.0` - player must be this far inside the new region
- `var imbalance_ratio: float = 1.25` - rebalance only if hottest > coldest * ratio
- `var entity_owner: Dictionary = {}` - entity id -> server
- `var players: Dictionary = {}` - player id -> {pos, state, transfer, ghosts}
- `var transfers: Dictionary = {}` - transfer id -> {player, from, to, state, payload}

## Functions

### `setup`

```gdscript
func setup(p_cols: int, p_rows: int, p_cell: float, p_servers: int) -> void
```

### `region_count`

```gdscript
func region_count() -> int
```

### `region_of`

```gdscript
func region_of(pos: Vector2) -> int
```

### `owner_at`

```gdscript
func owner_at(pos: Vector2) -> int
```

### `server_loads`

```gdscript
func server_loads(loads: Array) -> Array
```

### `assign_initial`

```gdscript
func assign_initial(loads: Array) -> void
```

Greedy LPT: heaviest regions first onto the least-loaded server (ties: fewest regions).

### `rebalance`

```gdscript
func rebalance(loads: Array) -> Array
```

Returns [{region, from, to}] and applies them. Does nothing while loads are within the
hysteresis band, and only moves a region when that strictly lowers the peak load.

### `claim_entity`

```gdscript
func claim_entity(entity_id: String, server: int) -> void
```

### `owner_of`

```gdscript
func owner_of(entity_id: String) -> int
```

### `entities_on`

```gdscript
func entities_on(server: int) -> Array
```

### `ghost_servers`

```gdscript
func ghost_servers(pos: Vector2, owner: int) -> Array
```

Servers (other than `owner`) whose regions fall within border_margin of pos.

### `handoff_needed`

```gdscript
func handoff_needed(player_pos: Vector2, current_server: int) -> int
```

Target server if the player should be handed off, else -1.

### `track_player`

```gdscript
func track_player(player_id: String, pos: Vector2, server: int) -> void
```

### `update_player`

```gdscript
func update_player(player_id: String, pos: Vector2) -> Dictionary
```

Moves the player; returns {"ghosts": Array, "handoff_to": int}.

### `begin_transfer`

```gdscript
func begin_transfer(player_id: String, to_server: int, transfer_id: String) -> String
```

Freezes the player. Idempotent per transfer id; returns the id or "" if rejected.

### `send_state`

```gdscript
func send_state(transfer_id: String, payload: Dictionary) -> bool
```

### `ack_transfer`

```gdscript
func ack_transfer(transfer_id: String) -> bool
```

Destination confirms it has the state.

### `release_transfer`

```gdscript
func release_transfer(transfer_id: String) -> bool
```

Source releases authority; ownership flips to the destination. Idempotent.

### `abort_transfer`

```gdscript
func abort_transfer(transfer_id: String) -> bool
```

Cancels an unfinished transfer (e.g. destination timeout); player unfreezes on the source.

_1 private function(s) starting with `_` are not listed._
