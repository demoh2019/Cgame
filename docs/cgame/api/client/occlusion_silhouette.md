# occlusion_silhouette.gd

> Keeps characters readable behind buildings and trees (Diablo / PoE X-ray): a material_overlay pass with an inverted depth test draws a tinted rim only where ...

`res://scripts/client/occlusion_silhouette.gd`

## Overview

Keeps characters readable behind buildings and trees (Diablo / PoE X-ray):
a material_overlay pass with an inverted depth test draws a tinted rim only
where the character is hidden. One shared material; no extra nodes.

## Constants

- `const SHADER := preload("res://assets/shaders/occlusion_silhouette.gdshader")`
- `const SELF_TINT := Color(0.35, 0.85, 1.0, 0.55)`

## Functions

### `material_for`

```gdscript
static func material_for(tint: Color) -> ShaderMaterial
```

### `apply`

```gdscript
static func apply(model: Node, tint: Color = SELF_TINT, enabled: bool = true) -> int
```

Applies (or with enabled=false removes) the overlay on every mesh of a model.

