# pooled_burst.gd

> A one-shot VFX emitter with resources allocated only once per pooled instance.

`res://scripts/client/pooled_burst.gd`

## Overview

A one-shot VFX emitter with resources allocated only once per pooled instance.

## Functions

### `on_pool_created`

```gdscript
func on_pool_created() -> void
```

### `on_pool_acquired`

```gdscript
func on_pool_acquired(pool: Node) -> void
```

### `configure_burst`

```gdscript
func configure_burst(color: Color, count: int, speed: float, seconds: float, size: float, gravity_strength: float, upward: float) -> void
```

### `on_pool_released`

```gdscript
func on_pool_released() -> void
```

_1 private function(s) starting with `_` are not listed._
