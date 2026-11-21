# hover_outline.gd

> Hover highlight for what the mouse points at (UE custom-depth outlines, Diablo / Path of Exile target highlight): an inverted-hull material_overlay on the mo...

`res://scripts/client/hover_outline.gd`

## Overview

Hover highlight for what the mouse points at (UE custom-depth outlines, Diablo /
Path of Exile target highlight): an inverted-hull material_overlay on the model
nearest the cursor's ground point. Display-only; one overlay at a time.

## Constants

- `const SHADER := preload("res://assets/shaders/hover_outline.gdshader")`
- `const PICK_RADIUS := 1.6`

## Functions

### `color_for`

```gdscript
static func color_for(kind: String) -> Color
```

### `material_for`

```gdscript
static func material_for(kind: String) -> ShaderMaterial
```

### `set_target`

```gdscript
func set_target(target: Dictionary) -> void
```

`target` is {"node": Node3D, "kind": String} or empty.

_1 private function(s) starting with `_` are not listed._
