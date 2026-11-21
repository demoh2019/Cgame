# destruction_replication.gd

> Compact replication of mass destruction state.

`res://scripts/shared/destruction_replication.gd`

## Overview

Compact replication of mass destruction state.

One class serves both ends: the server calls apply_damage() and delta_since();
a client mirror calls apply_delta(). State per object is tiny (quantised health
bucket, fractured flag, deterministic fracture seed, broken-chunk bitmask) and
is sent as ABSOLUTE values, so a delta is idempotent and a lost/duplicated
packet only costs bandwidth, never correctness.

Design follows the usual snapshot-delta pattern (per-entity change version vs
client-acked baseline, varint + bit-packed encoding as in Quake 3 / Valve
Source / Glenn Fiedler's "Snapshot Compression" articles) - common
technique, no third-party code. Varints are LEB128 (public domain format).

Wire format: varint target_version, varint baseline_version, varint count,
then per object: varint (id - previous_id - 1), byte flags
(bits 0-3 health bucket, bit 4 fractured), and when fractured a varint
fracture_seed (24 bit) and varint broken_chunks (32 bit mask).

## Constants

- `enum Result { APPLIED, STALE, GAP, MALFORMED }`
- `const BUCKETS := 15`
- `const CHUNKS := 32`
- `const FRACTURE_FRACTION := 0.5`
- `const SEED_MASK := 0xFFFFFF`
- `const FLAG_FRACTURED := 16`

## Functions

### `setup`

```gdscript
func setup(count: int, p_world_seed: int = 1) -> void
```

### `object_count`

```gdscript
func object_count() -> int
```

### `set_max_health`

```gdscript
func set_max_health(id: int, hp: float) -> void
```

### `health_bucket`

```gdscript
func health_bucket(id: int) -> int
```

### `health_fraction`

```gdscript
func health_fraction(id: int) -> float
```

### `is_fractured`

```gdscript
func is_fractured(id: int) -> bool
```

### `is_destroyed`

```gdscript
func is_destroyed(id: int) -> bool
```

### `fracture_seed`

```gdscript
func fracture_seed(id: int) -> int
```

### `broken_chunks`

```gdscript
func broken_chunks(id: int) -> int
```

### `consume_fracture_events`

```gdscript
func consume_fracture_events() -> Array[Dictionary]
```

Fracture events (id, seed, mask) since last call: clients spawn identical debris from them.

### `consume_destroyed`

```gdscript
func consume_destroyed() -> Array[int]
```

Ids that reached health 0 since last call: feed to NavmeshCarving.on_destroyed().

### `make_fracture_seed`

```gdscript
static func make_fracture_seed(p_world_seed: int, id: int, impact_point: Vector2) -> int
```

Deterministic seed: every peer derives the same debris layout from (world, id, quantised impact).

### `initial_chunk_mask`

```gdscript
static func initial_chunk_mask(p_seed: int) -> int
```

Initial set of broken chunks for a fresh fracture (about a quarter of them).

### `chunk_for_impact`

```gdscript
static func chunk_for_impact(p_seed: int, impact_point: Vector2) -> int
```

### `apply_damage`

```gdscript
func apply_damage(id: int, amount: float, impact_point: Vector2 = Vector2.ZERO) -> bool
```

Applies damage on the server. Returns true if replicated state changed.

### `delta_since`

```gdscript
func delta_since(baseline_version: int) -> PackedByteArray
```

Encodes every object changed after baseline_version (the client's acked version).

### `full_state_size`

```gdscript
func full_state_size() -> int
```

Size of a full-state packet, for bandwidth comparison.

### `delta_size_only`

```gdscript
func delta_size_only(baseline_version: int) -> int
```

### `stats`

```gdscript
func stats() -> Dictionary
```

### `apply_delta`

```gdscript
func apply_delta(bytes: PackedByteArray) -> Result
```

Applies a delta. Stale/duplicate deltas (target <= our version) are ignored; a delta whose
baseline is newer than what we hold would skip history and is rejected (GAP: ack the
old version again so the server resends from there).

_3 private function(s) starting with `_` are not listed._
