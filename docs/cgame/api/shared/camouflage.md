# camouflage.gd

> Classless equipment stealth.

`res://scripts/shared/camouflage.gd`

## Overview

Classless equipment stealth. Called with server-verified equipment ownership.
Noise still makes survivors audible, and blood scent is a separate channel.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`

## Functions

### `visual_signature`

```gdscript
static func visual_signature(armor_id: String, owned: bool, noise_timer: float, alive: bool = true) -> float
```

