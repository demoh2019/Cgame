# skills_panel.gd

> The skill tree window (K): one tab per branch, every skill with its level and progress, the perks it unlocks, and the bonuses you have right now.

`res://scripts/client/skills_panel.gd`

## Overview

The skill tree window (K): one tab per branch, every skill with its level and progress, the perks it unlocks,
and the bonuses you have right now. Buying a perk is a request to the server, which decides.

## Constants

- `const Skills = preload("res://scripts/shared/skills.gd")`

## Functions

### `setup`

```gdscript
func setup(p_client) -> void
```

### `toggle`

```gdscript
func toggle() -> void
```

_3 private function(s) starting with `_` are not listed._
