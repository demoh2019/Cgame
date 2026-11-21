# camp_provisions.gd

> Atomic, private party supply handoff at one server-owned live campfire.

`res://scripts/shared/camp_provisions.gd`

## Overview

Atomic, private party supply handoff at one server-owned live campfire.
Neither the fire ID, item IDs nor quantities are client-authored.

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const PartyAid = preload("res://scripts/shared/party_aid.gd")`
- `const PartyFeast = preload("res://scripts/shared/party_feast.gd")`
- `const PACKAGES := {`

## Functions

### `package_items`

```gdscript
static func package_items(kind: String) -> Dictionary
```

### `shared_fire`

```gdscript
static func shared_fire(campfires: Dictionary, source: Vector3, target: Vector3, now: float) -> bool
```

Both survivors must be close and within the SAME burning fire's radius.

### `transfer`

```gdscript
static func transfer(source, target, kind: String) -> String
```

Stage both backpacks: the donor never loses items if the recipient is full.

