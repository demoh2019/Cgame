# lens_dirt.gd

> Procedural lens dirt for bloom (Unreal "Bloom Dirt Mask", Battlefield / Mirror's Edge look): bright light sources reveal smudges and specks on the "lens".

`res://scripts/client/lens_dirt.gd`

## Overview

Procedural lens dirt for bloom (Unreal "Bloom Dirt Mask", Battlefield / Mirror's
Edge look): bright light sources reveal smudges and specks on the "lens".
Godot multiplies glow by Environment.glow_map, so the mask is an HDR texture
around 0.7 with smudges above 1: glow is boosted where the lens is dirty.

## Constants

- `const WIDTH := 192`
- `const HEIGHT := 108`

## Functions

### `texture`

```gdscript
static func texture() -> Texture2D
```

### `strength`

```gdscript
static func strength(level: int, rendering_method: String) -> float
```

glow_map_strength for a tier/renderer (0 = off).

### `apply`

```gdscript
static func apply(env: Environment, level: int, rendering_method: String) -> void
```

