# blob_shadow.gd

> Soft round "blob" contact shadows under characters for when real sun shadows are off (Performance tier) - the Diablo II / WoW Classic fallback that keeps cha...

`res://scripts/client/blob_shadow.gd`

## Overview

Soft round "blob" contact shadows under characters for when real sun shadows
are off (Performance tier) - the Diablo II / WoW Classic fallback that keeps
characters grounded instead of floating. One shared mesh and material.

## Constants

- `const GROUP := "aa_blob_shadows"`
- `const NODE_NAME := &"BlobShadow"`

## Functions

### `shared_mesh`

```gdscript
static func shared_mesh() -> PlaneMesh
```

### `wanted`

```gdscript
static func wanted(sun_shadows_enabled: bool) -> bool
```

Blob shadows show only while the real directional shadows are disabled.

### `make`

```gdscript
static func make(visible: bool) -> MeshInstance3D
```

