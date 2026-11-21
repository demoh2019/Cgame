# save_migrations.gd

> Versioned save-data migrations.

`res://scripts/server/save_migrations.gd`

## Overview

```text
Versioned save-data migrations.

A registry of single-step migrations {from_version, to_version, migrate: Callable}. migrate()
walks the chain from data["version"] to the target, never mutating the caller's dictionary,
refusing gaps and downgrades. verify_roundtrip() proves a sample survives migration and
still passes a validator, so every new schema bump ships with a fixture.

Pattern credit: ordered, idempotent schema-migration chains as used by Rails/ActiveRecord
(MIT), Flyway (Apache-2.0) and SQLite "user_version" upgrade ladders (public domain).
This file is original GDScript; no third-party code was copied.

Example character-save shape (version field "version"):
  v1: {version:1, health, money}
  v2: money renamed to silver                      (example_v1_to_v2)
  v3: new "focus" meter added, default 100.0       (example_v2_to_v3)
To add a migration: write a static func taking a Dictionary (already a deep copy, mutate
freely) and returning the upgraded dictionary WITHOUT touching "version" (the runner stamps
it), then register it with register(from, to, Callable). Steps must be +1 and pure.
```

## Constants

- `const CHARACTER_LATEST := 3`

## Functions

### `character_registry`

```gdscript
static func character_registry()
```

Registry preloaded with the two example character migrations.

### `register`

```gdscript
func register(from_version: int, to_version: int, migrate_fn: Callable) -> bool
```

Returns false (and sets last_error) for non-forward steps or a duplicate from_version.

### `migrate`

```gdscript
func migrate(data: Dictionary, target_version: int) -> Dictionary
```

Returns the migrated deep copy, or {} with last_error set (gap, downgrade, bad version, step failure).

### `verify_roundtrip`

```gdscript
func verify_roundtrip(data: Dictionary, migrate_to: int, validate: Callable) -> Array[String]
```

Returns problems (empty = ok): migration failure, input mutated, wrong final version,
validator rejection, or a second migrate() call that is not a no-op.

### `example_v1_to_v2`

```gdscript
static func example_v1_to_v2(data: Dictionary) -> Dictionary
```

v1 -> v2: "money" is renamed "silver" (value preserved; an existing "silver" wins).

### `example_v2_to_v3`

```gdscript
static func example_v2_to_v3(data: Dictionary) -> Dictionary
```

v2 -> v3: adds the "focus" meter, defaulting to a full 100.0 when absent.

