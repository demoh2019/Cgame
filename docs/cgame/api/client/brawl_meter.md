# brawl_meter.gd

> First-person brawling HUD: a wind-up arc around the crosshair while a power blow charges (white, turning orange when it will stagger), and the Rage bar under...

`res://scripts/client/brawl_meter.gd`

## Overview

First-person brawling HUD: a wind-up arc around the crosshair while a power blow charges
(white, turning orange when it will stagger), and the Rage bar under it (pulses when ready).

## Constants

- `const STAGGER_CHARGE := 0.75`

## Functions

### `update_state`

```gdscript
func update_state(new_charge: float, is_charging: bool, new_rage: float, new_rage_seconds: float, delta: float) -> void
```

_2 private function(s) starting with `_` are not listed._
