# audio_mix_snapshots.gd

> (no header comment)

`res://scripts/client/audio_mix_snapshots.gd`

## Constants

- `const MAX_MIXES := 16` - Portable fallback for Cgame's AudioMixSnapshotController. Profile stage dB values are independent of user volume and temporary ducking.
- `const MAX_BUSES := 8`
- `const MAX_STAGE_DB := 30.0`
- `const MAX_FADE_SECONDS := 15.0`
- `const MAX_HOLD_SECONDS := 120.0`

## Functions

### `activate_mix`

```gdscript
static func activate_mix(mixes: Dictionary, source: String, offsets: Dictionary, fade_seconds: float = 1.0) -> bool
```

### `activate_timed_mix`

```gdscript
static func activate_timed_mix(mixes: Dictionary, source: String, offsets: Dictionary, attack_seconds: float = 0.2, hold_seconds: float = 3.0, release_seconds: float = 1.0) -> bool
```

A repeat re-arms the expiry timer without resetting a partially faded
weight. Equivalent to Cgame's bounded timed Control Bus Mix.

### `deactivate_mix`

```gdscript
static func deactivate_mix(mixes: Dictionary, source: String, fade_seconds: float = 1.0) -> bool
```

### `tick`

```gdscript
static func tick(mixes: Dictionary, delta: float) -> void
```

### `bus_offset_db`

```gdscript
static func bus_offset_db(mixes: Dictionary, bus: String) -> float
```

### `mix_weight`

```gdscript
static func mix_weight(mixes: Dictionary, source: String) -> float
```

### `mix_remaining_seconds`

```gdscript
static func mix_remaining_seconds(mixes: Dictionary, source: String) -> float
```

_1 private function(s) starting with `_` are not listed._
