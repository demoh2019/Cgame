# outpost_view.gd

> Siege outposts in the world: a banner pole whose flag shows the owner, a ring on the ground for the capture radius, and a floating label with the fortificati...

`res://scripts/client/outpost_view.gd`

## Overview

Siege outposts in the world: a banner pole whose flag shows the owner, a ring on the ground for the capture
radius, and a floating label with the fortification, the capture progress and any war in progress.

## Constants

- `const TerritoryControl = preload("res://scripts/shared/territory_control.gd")`
- `const ClothFlag = preload("res://scripts/client/cloth_flag.gd")`
- `const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")`
- `const HangingLantern = preload("res://scripts/client/hanging_lantern.gd")`

## Functions

### `update_from`

```gdscript
func update_from(client) -> void
```

_3 private function(s) starting with `_` are not listed._
