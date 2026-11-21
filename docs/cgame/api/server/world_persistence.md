# world_persistence.gd

> (no header comment)

`res://scripts/server/world_persistence.gd`

## Constants

- `const HousePieces = preload("res://scripts/shared/house_pieces.gd")`
- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const MarketBoard = preload("res://scripts/shared/market_board.gd")`
- `const MarketBids = preload("res://scripts/shared/market_bids.gd")`
- `const Farming = preload("res://scripts/shared/farming.gd")`
- `const GuildBank = preload("res://scripts/shared/guild_bank.gd")`
- `const GuildAlliances = preload("res://scripts/shared/guild_alliances.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const VERSION: int = 1`
- `const MAX_BYTES: int = 262144 # Barricades plus escrowed market listings.`
- `const MAX_ABS_COORD: float = 20000.0`
- `const MIN_ID: int = 5000000001`
- `const MAX_ID: int = 9007199254740000`
- `const MAX_OWNER_LENGTH: int = 128`

## Functions

### `capture`

```gdscript
static func capture(sim) -> Dictionary
```

### `validate`

```gdscript
static func validate(data: Variant, sim) -> Dictionary
```

Do all checks before adding a single blocker or modifying any active wall.
Refuse a snapshot from another seed or terrain layout, including overlapping
terrain obstacles, neighboring restored walls and impossible owner quotas.

### `restore`

```gdscript
static func restore(sim, data: Variant) -> bool
```

### `valid_world_path`

```gdscript
static func valid_world_path(path: String) -> bool
```

Prevent a --world-save argument from escaping the Cgame user-data tree.
This is path normalization, not a defense against attacker-created symlinks
on the host filesystem (administrators must secure the data directory).

### `save`

```gdscript
static func save(sim, path: String) -> bool
```

A successful second save retains one previous complete checkpoint in .bak.
The backup is not loaded automatically, because that could resurrect items
already salvaged/destroyed after the previous save.

### `load`

```gdscript
static func load(sim, path: String) -> bool
```

_12 private function(s) starting with `_` are not listed._
