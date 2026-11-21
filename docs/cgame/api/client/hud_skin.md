# hud_skin.gd

> The heads-up display's look: a vitals card with animated bars and status chips, a zone and clock strip, a quest card under the minimap, an action bar with co...

`res://scripts/client/hud_skin.gd`

## Overview

The heads-up display's look: a vitals card with animated bars and status chips, a zone and clock strip, a quest card under
the minimap, an action bar with cooldown sweeps, an XP strip, a banner for big moments and screen-edge feedback (low health
pulse, damage flash). It only draws what `client.you` already says; nothing here can change the game.
The old text labels of hud.gd stay alive (hidden) and F3 shows them as a details panel.

## Constants

- `const UiSettings = preload("res://scripts/client/ui_settings.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Combat = preload("res://scripts/shared/combat.gd")`
- `const Contracts = preload("res://scripts/shared/contracts.gd")`
- `const FirstSteps = preload("res://scripts/client/first_steps.gd")`
- `const WorldCycle = preload("res://scripts/shared/world_cycle.gd")`
- `const Evasion = preload("res://scripts/shared/evasion.gd")`
- `const Skills = preload("res://scripts/shared/skills.gd")`
- `const ItemIcons = preload("res://scripts/client/item_icons.gd")`
- `const INK := Color(0.96, 0.97, 1.0)`
- `const DIM := Color(0.72, 0.76, 0.84)`
- `const CARD := Color(0.05, 0.06, 0.09, 0.82)`
- `const EDGE := Color(1.0, 0.86, 0.5, 0.35)`
- `const GOLD := Color(0.95, 0.78, 0.35)`
- `const ZONE_COLORS := [Color(0.35, 0.85, 0.45), Color(0.95, 0.82, 0.3), Color(0.95, 0.45, 0.3), Color(0.78, 0.3, 0.95)]`
- `const ZONE_TITLES := ["GREEN ZONE", "YELLOW ZONE", "RED ZONE", "BLACK ZONE"]`
- `const WOOD := Color(0.24, 0.16, 0.1)`
- `const BRONZE := Color(0.72, 0.55, 0.3)`
- `const PARCHMENT := Color(0.93, 0.86, 0.72)`
- `const INK_DARK := Color(0.24, 0.15, 0.08)`

## Functions

### `setup`

```gdscript
func setup(p_client) -> void
```

### `banner`

```gdscript
func banner(text: String, color: Color = GOLD) -> void
```

_42 private function(s) starting with `_` are not listed._
