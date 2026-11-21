# ui_theme.gd

> One look for the whole interface, in the manner of the classic online RPGs: windows are warm parchment cards with a dark wood frame, dark ink text, brown but...

`res://scripts/client/ui_theme.gd`

## Overview

One look for the whole interface, in the manner of the classic online RPGs: windows are warm parchment cards with a
dark wood frame, dark ink text, brown buttons and a red one for the main action; text that floats over the world
(log, prompts, title screen) stays light with an outline. `apply` gives every window of a HUD layer the parchment
theme and everything else the light one, so the HUD code does not need to know about it.

## Constants

- `const GOLD := Color(0.92, 0.76, 0.34)`
- `const PANEL := Color(0.06, 0.07, 0.1, 0.9)`
- `const PAPER := Color(0.93, 0.86, 0.72)`
- `const PAPER_DARK := Color(0.84, 0.75, 0.6)`
- `const WOOD := Color(0.33, 0.22, 0.13)`
- `const INK := Color(0.24, 0.15, 0.08)`
- `const INK_SOFT := Color(0.42, 0.32, 0.22)`
- `const HEADING := Color(0.45, 0.22, 0.1)`
- `const BUTTON := Color(0.47, 0.32, 0.19)`
- `const ACCENT := Color(0.66, 0.2, 0.14) # The red of a confirm button.`
- `const CREAM := Color(0.99, 0.95, 0.86)`

## Functions

### `get_theme`

```gdscript
static func get_theme() -> Theme
```

The light theme for text over the game world and the title screen.

### `paper_theme`

```gdscript
static func paper_theme() -> Theme
```

Parchment for windows: inventory, crafting, skills, help.

### `apply`

```gdscript
static func apply(layer: CanvasLayer) -> void
```

Windows (panels) of a HUD layer get parchment, everything else the light theme; colored bars it created are rounded.

_4 private function(s) starting with `_` are not listed._
