# graphics_shadow_atlas.gd

> Renderer-aware directional shadow atlas budgets for the game's single sun.

`res://scripts/client/graphics_shadow_atlas.gd`

## Overview

Renderer-aware directional shadow atlas budgets for the game's single sun.
Unity HDRP and Unreal size the shadow-map pool against quality and target
hardware. This uses Godot's existing global shadow atlas: no extra lights,
shader texture fetches, shadow-casting nodes, or network/world state.

Resizing a shadow atlas reallocates GPU storage. Never do it per frame:
GraphicsQuality.apply() invokes this only when its resolved plan changes.
32-bit depth on Ultra Forward+ improves depth precision (less shadow acne)
at a real memory cost; Compatibility/Mobile keep the 16-bit budget.

## Functions

### `plan`

```gdscript
static func plan(level: int, rendering_method: String) -> Dictionary
```

### `needs_apply`

```gdscript
static func needs_apply(previous: Dictionary, next: Dictionary) -> bool
```

Pure plan comparison, useful for headless regression tests. Avoids
reallocating the global shadow atlas for unchanged/duplicate requests.

### `apply`

```gdscript
static func apply(level: int, rendering_method: String) -> void
```

A global RenderingServer resource, not a per-viewport setting. The game's
solo and multiplayer clients share one global configuration in each process.

