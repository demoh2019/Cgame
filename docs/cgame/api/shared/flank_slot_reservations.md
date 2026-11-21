# flank_slot_reservations.gd

> (no header comment)

`res://scripts/shared/flank_slot_reservations.gd`

## Constants

- `const MAX_ACTIVE_CLAIMS := 2048` - Portable, server-owned SmartObjectSlotReservations fallback for stock Godot. No wall clock, RNG, client RPCs or positional state; ticked by GameServer.
- `const MAX_CANDIDATES := 16`
- `const MAX_LEASE_SECONDS := 5.0`

## Functions

### `try_claim_first`

```gdscript
func try_claim_first(slot_ids: PackedInt64Array, actor_id: int, lease_seconds: float) -> int
```

### `try_claim_first_priority`

```gdscript
func try_claim_first_priority(slot_ids: PackedInt64Array, actor_id: int, lease_seconds: float, priority: int) -> int
```

### `refresh_claim`

```gdscript
func refresh_claim(slot_id: int, actor_id: int, lease_seconds: float, occupied: bool) -> bool
```

One indexed heartbeat for an already-owned flank slot. No candidate
scan, priority change, lease resurrection or cross-actor occupancy writes.
Matches native SmartObjectSlotReservations.refresh_claim() exactly.

### `set_slot_occupied`

```gdscript
func set_slot_occupied(slot_id: int, actor_id: int, occupied: bool) -> bool
```

### `is_slot_occupied`

```gdscript
func is_slot_occupied(slot_id: int) -> bool
```

### `release_slot`

```gdscript
func release_slot(slot_id: int, actor_id: int) -> bool
```

### `release_actor`

```gdscript
func release_actor(actor_id: int) -> int
```

### `advance_time`

```gdscript
func advance_time(delta: float) -> void
```

### `clear`

```gdscript
func clear() -> void
```

### `get_owner`

```gdscript
func get_owner(slot_id: int) -> int
```

### `get_actor_slot`

```gdscript
func get_actor_slot(actor_id: int) -> int
```

O(1) owned-slot lookup, matching native SmartObjectSlotReservations.
The zombie uses this to reject a cached flank goal after its lease expires.

### `get_claim_count`

```gdscript
func get_claim_count() -> int
```

