# expedition_atlas.gd

> The owner-only expedition journal shown on the full island map.

`res://scripts/shared/expedition_atlas.gd`

## Overview

The owner-only expedition journal shown on the full island map. All
destinations originate from the authenticated "you" snapshot, never from
another player's replication, and are purely visual navigation targets.

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")`

## Functions

### `objectives`

```gdscript
static func objectives(you: Variant) -> Array[Dictionary]
```

Draw order is stable so goals do not jump when values change.
No arbitrary user-controlled names, rewards, or inventory are displayed.

### `find`

```gdscript
static func find(objectives_list: Array[Dictionary], key: String) -> Dictionary
```

_1 private function(s) starting with `_` are not listed._
