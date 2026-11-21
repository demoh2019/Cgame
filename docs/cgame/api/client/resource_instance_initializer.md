# resource_instance_initializer.gd

> (no header comment)

`res://scripts/client/resource_instance_initializer.gd`

## Constants

- `const MIN_NATIVE_BATCH := 12` - Initial placement of server-owned Albion After chunk resources. Dense 3D+RGBA groups use ONE full MultiMesh buffer upload instead of separate script/renderer updates for every tree, ore and world object. For tiny groups or custom shader data, preserve individual legacy setters.

## Functions

### `initialize`

```gdscript
static func initialize(mm: MultiMesh, transforms: Array, colors: PackedColorArray) -> bool
```

Never update the renderer until ALL transforms and colors are valid.
Preserve existing custom instance data when a caller uses that format.

_2 private function(s) starting with `_` are not listed._
