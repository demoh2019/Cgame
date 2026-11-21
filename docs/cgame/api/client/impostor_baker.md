# impostor_baker.gd

> Runtime impostor generation (UE5 Impostor Baker, Unity Amplify Impostors).

`res://scripts/client/impostor_baker.gd`

## Overview

Runtime impostor generation (UE5 Impostor Baker, Unity Amplify Impostors).
Each mesh is rendered once from FRAMES yaw angles into a horizontal atlas
inside an isolated SubViewport world, then cached for every far field.
Headless servers and tests never bake; fields simply stay hidden.

## Constants

- `const FRAMES := 8`
- `const RESOLUTION := 128`
- `const SHADER := preload("res://assets/shaders/impostor.gdshader")`

## Functions

### `frame_size`

```gdscript
static func frame_size(mesh: Mesh) -> Vector2
```

Square bake extent and vertical center of a mesh (shared by bake and quad).

### `can_bake`

```gdscript
static func can_bake() -> bool
```

### `cached`

```gdscript
static func cached(mesh: Mesh) -> Texture2D
```

### `material_for`

```gdscript
static func material_for(mesh: Mesh, atlas: Texture2D) -> ShaderMaterial
```

### `request`

```gdscript
static func request(mesh: Mesh, tree: SceneTree, done: Callable) -> void
```

Calls done(atlas) once the mesh is baked (immediately when cached).

### `clear_cache`

```gdscript
static func clear_cache() -> void
```

_2 private function(s) starting with `_` are not listed._
