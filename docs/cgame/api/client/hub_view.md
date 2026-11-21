# hub_view.gd

> The hub town: a paved plaza with the fountain, a ring of houses, lamp posts and the workbench.

`res://scripts/client/hub_view.gd`

## Overview

The hub town: a paved plaza with the fountain, a ring of houses, lamp posts and the workbench.
What stands where comes from WorldGen.hub_structures(), the same list the server collides with.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const Assets = preload("res://scripts/client/assets.gd")`
- `const Meshes = preload("res://scripts/client/meshes.gd")`
- `const OutdoorReflectionBudget = preload("res://scripts/client/outdoor_reflection_budget.gd")`
- `const PLAZA_SHADER := """`
- `const FOUNTAIN_SHADER := """`

## Functions

### `build`

```gdscript
func build(world) -> void
```

_5 private function(s) starting with `_` are not listed._
