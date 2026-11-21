# off_mesh_links.gd

> Automatic off-mesh link generation from a heightfield.

`res://scripts/shared/off_mesh_links.gd`

## Overview

```text
Automatic off-mesh link generation from a heightfield.
Inspired by Recast/Detour off-mesh connections: traversals the walkable grid cannot express
(ledge drops, small climbs, short gaps) become explicit links the navigation layer can use.

Link kinds:
  "drop" - one-way ledge down between adjacent walkable cells (height gap > walk_step, <= max_drop)
  "jump" - bidirectional small climb: adjacent walkable cells, gap in (walk_step, max_jump_up]
  "gap"  - bidirectional hop over 1..max_gap unwalkable cells between walkable cells of similar height
Cells are scanned row by row (y, then x) towards +x then +y, so order is deterministic
and every pair appears once.
```

## Constants

- `const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]`

## Functions

### `generate`

```gdscript
static func generate(width: int, height: int, height_at: Callable, walkable: Callable, max_drop := 3.0, max_jump_up := 1.2, max_gap := 2, walk_step := 0.5) -> Array
```

_3 private function(s) starting with `_` are not listed._
