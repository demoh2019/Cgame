# ground_contact_ao.gd

> Cheap CPU-baked contact-occlusion mask for streamed terrain.

`res://scripts/client/ground_contact_ao.gd`

## Overview

Cheap CPU-baked contact-occlusion mask for streamed terrain. The mask is
visual only: no collisions, server data or extra shadow-map passes.
One 64x64 L8 texture (4 KiB of raw pixels) per above-ground chunk.

## Constants

- `const SIZE := 64`
- `const EDGE_FADE_METERS := 2.5`

## Functions

### `mask_bytes`

```gdscript
static func mask_bytes(origin: Vector2, chunk_size: float, nodes: Array, structures: Array, hidden_ids: Dictionary = {}) -> PackedByteArray
```

### `create_texture`

```gdscript
static func create_texture(origin: Vector2, chunk_size: float, nodes: Array, structures: Array, hidden_ids: Dictionary = {}) -> ImageTexture
```

_1 private function(s) starting with `_` are not listed._
