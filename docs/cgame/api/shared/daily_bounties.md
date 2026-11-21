# daily_bounties.gd

> One UTC-rotating, account-persisted camp bounty per real-world day.

`res://scripts/shared/daily_bounties.gd`

## Overview

One UTC-rotating, account-persisted camp bounty per real-world day.
The dedicated server selects the mission from its own UTC clock. A client
cannot submit progress, reward quantities, a mission ID or an alternate day.

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const SaveValidation = preload("res://scripts/shared/save_validation.gd")`
- `const SECONDS_PER_DAY := 86400.0`
- `const MAX_DAY := 100000`
- `const BOUNTIES := [`

## Functions

### `utc_day`

```gdscript
static func utc_day() -> int
```

### `assignment`

```gdscript
static func assignment(day: int) -> Dictionary
```

### `empty_state`

```gdscript
static func empty_state() -> Dictionary
```

### `valid_state`

```gdscript
static func valid_state(data: Variant) -> bool
```

### `refresh`

```gdscript
static func refresh(state: Dictionary, today: int) -> bool
```

Returning a new-day flag allows the owner to dirty the persistent character.
A backwards-moving host clock never reopens a completed daily bounty.

### `description`

```gdscript
static func description(state: Dictionary, today: int) -> String
```

### `record_kill`

```gdscript
static func record_kill(state: Dictionary, today: int) -> bool
```

### `record_crate`

```gdscript
static func record_crate(state: Dictionary, today: int, crate_id: int) -> bool
```

Only invoke after the server confirms a real, previously unopened crate.

### `claim`

```gdscript
static func claim(carried, state: Dictionary, today: int) -> Dictionary
```

Transactional delivery and reward: no partial debit or free prize on full bags.

