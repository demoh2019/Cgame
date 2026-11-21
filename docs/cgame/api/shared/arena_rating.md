# arena_rating.gd

> (no header comment)

`res://scripts/shared/arena_rating.gd`

## Constants

- `const START_RATING := 1200` - Optional ranked PvP sparring built on existing no-loot, consent-only hub duels. Only the server resolves knockouts/forfeits and changes persisted rating.
- `const MIN_RATING := 600`
- `const MAX_RATING := 2400`
- `const MAX_RECORD := 100000`
- `const K_FACTOR := 32`
- `const REMATCH_SECONDS := 1200.0`
- `const MAX_PAIRS := 2048`

## Functions

### `valid_rating`

```gdscript
static func valid_rating(value: Variant) -> bool
```

### `valid_record`

```gdscript
static func valid_record(value: Variant) -> bool
```

### `tier`

```gdscript
static func tier(value: int) -> String
```

### `pair_key`

```gdscript
static func pair_key(first, second) -> String
```

### `eligibility`

```gdscript
static func eligibility(first, second, now: float, history: Dictionary) -> String
```

Nakama-authenticated accounts only: guest / peer IDs can be recycled.

### `settle`

```gdscript
static func settle(winner, loser, now: float, history: Dictionary) -> Dictionary
```

