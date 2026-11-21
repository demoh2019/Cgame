# arena_matchmaking.gd

> (no header comment)

`res://scripts/shared/arena_matchmaking.gd`

## Constants

- `const ArenaRating = preload("res://scripts/shared/arena_rating.gd")` - One-server, opt-in ranked duel matchmaking using real Nakama account IDs. A queued survivor consents to automatically accept the chosen opponent.
- `const TrainingDuel = preload("res://scripts/shared/training_duel.gd")`
- `const MAX_QUEUED := 64`
- `const BASE_ELO_GAP := 125`
- `const ELO_GAP_STEP := 30`
- `const ELO_GAP_STEP_SECONDS := 20.0`
- `const MAX_ELO_GAP := 350`
- `const CHECK_EVERY_TICKS := 10`

## Functions

### `join_reason`

```gdscript
static func join_reason(world, player, now: float) -> String
```

### `gap_after`

```gdscript
static func gap_after(wait_seconds: float) -> int
```

### `entry_valid`

```gdscript
static func entry_valid(entry: Dictionary, player, world, now: float, duels: Dictionary, invitations: Dictionary) -> bool
```

Both participants must be eligible, uninvited and still the same
authenticated Player instances that opted into queue.

### `choose`

```gdscript
static func choose(queue: Dictionary, players: Dictionary, world, now: float, cooldowns: Dictionary, duels: Dictionary, invitations: Dictionary) -> Array[int]
```

Prefer closest Elo of all eligible pairs, tie-breaking by time in queue
then peer numbers. This is a capped, deterministic O(64^2) scan.

