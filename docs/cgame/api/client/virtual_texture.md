# virtual_texture.gd

> Sparse virtual texture: page table, feedback-driven requests, LRU physical page cache, mip fallback and an indirection image for shaders.

`res://scripts/client/virtual_texture.gd`

## Overview

Sparse virtual texture: page table, feedback-driven requests, LRU physical page cache,
mip fallback and an indirection image for shaders.

Original implementation (no third-party code copied). Concepts follow the publicly
documented sparse virtual texturing designs: Sean Barrett, "Sparse Virtual Textures"
(GDC 2008 talk, ideas only) and the page-table/indirection scheme described for
Unreal Engine Runtime Virtual Texture (concepts only, no source used).

Page keys encode (mip, x, y) with pack_page(). The lowest (1-page) mip is pinned and
always resident, so every virtual page can fall back to some resident ancestor.
Atlas layout: physical slot (sx, sy) covers (page_size + 2 * border) pixels square;
the page content sits inside, the border is edge-replicated for bilinear filtering.

## Documented variables

- `var provider: Callable = Callable()` - Callable(mip: int, page_x: int, page_y: int) -> Image (page_size x page_size content).

## Functions

### `pack_page`

```gdscript
static func pack_page(mip: int, x: int, y: int) -> int
```

### `page_mip`

```gdscript
static func page_mip(key: int) -> int
```

### `page_x`

```gdscript
static func page_x(key: int) -> int
```

### `page_y`

```gdscript
static func page_y(key: int) -> int
```

### `setup`

```gdscript
func setup(p_virtual_size: int, p_page_size: int, p_physical_x: int, p_physical_y: int, p_border: int = 4) -> void
```

### `pages_at`

```gdscript
func pages_at(mip: int) -> int
```

### `request_from_feedback`

```gdscript
func request_from_feedback(feedback: PackedInt32Array) -> void
```

Feedback entries are pack_page() keys read back from the screen-space feedback pass.
Duplicates are folded; resident pages are touched (LRU) and counted as hits.

### `update`

```gdscript
func update(max_uploads_per_frame: int) -> int
```

### `indirection_image`

```gdscript
func indirection_image() -> Image
```

### `physical_atlas`

```gdscript
func physical_atlas() -> Image
```

### `lookup`

```gdscript
func lookup(uv: Vector2, mip: int) -> Dictionary
```

### `is_resident`

```gdscript
func is_resident(mip: int, x: int, y: int) -> bool
```

### `resident_count`

```gdscript
func resident_count() -> int
```

### `pending_count`

```gdscript
func pending_count() -> int
```

### `stats`

```gdscript
func stats() -> Dictionary
```

_7 private function(s) starting with `_` are not listed._
