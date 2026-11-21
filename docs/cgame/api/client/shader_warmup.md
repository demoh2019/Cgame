# shader_warmup.gd

> Shader / pipeline precompilation (UE5 PSO precaching, Unity ShaderVariantCollection.WarmUp): during loading every spatial shader of the game is drawn once on...

`res://scripts/client/shader_warmup.gd`

## Overview

Shader / pipeline precompilation (UE5 PSO precaching, Unity
ShaderVariantCollection.WarmUp): during loading every spatial shader of the
game is drawn once on a sub-pixel quad in front of the camera, so the
driver compiles its pipelines before combat instead of mid-fight.

## Constants

- `const SHADER_DIRS := ["res://assets/shaders", "res://shaders"]`
- `const FRAMES_VISIBLE := 3`

## Functions

### `shader_paths`

```gdscript
static func shader_paths() -> PackedStringArray
```

### `spatial_shaders`

```gdscript
static func spatial_shaders() -> Array[Shader]
```

### `start`

```gdscript
static func start(camera: Camera3D) -> Node3D
```

Attaches a warm-up rig to the camera; it frees itself after a few frames.

_1 private function(s) starting with `_` are not listed._
