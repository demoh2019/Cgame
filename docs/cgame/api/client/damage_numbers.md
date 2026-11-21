# damage_numbers.gd

> Floating combat numbers (Diablo / WoW / Lost Ark): each hit pops a number above the target that springs up, drifts sideways and fades.

`res://scripts/client/damage_numbers.gd`

## Overview

Floating combat numbers (Diablo / WoW / Lost Ark): each hit pops a number above
the target that springs up, drifts sideways and fades. Heavy hits are bigger
and gold, damage taken by you is red. Pooled Label3D nodes; no allocation per hit.

## Constants

- `const POOL_SIZE := 24`
- `const LIFE := 0.85`
- `const HEAVY_HIT := 35.0`

## Functions

### `style`

```gdscript
static func style(damage: float, on_me: bool) -> Array
```

Colour and size for a hit: (color, font scale).

### `pop`

```gdscript
static func pop(t: float) -> float
```

Pop-in then settle: scale multiplier over normalized age (0..1).

### `on_event`

```gdscript
func on_event(event: Dictionary, at: Vector3, my_peer: int) -> void
```

_2 private function(s) starting with `_` are not listed._
