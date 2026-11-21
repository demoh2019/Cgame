# graphics_skin_scattering.gd

> Skin-only subsurface scattering for imported character bodies and heads.

`res://scripts/client/graphics_skin_scattering.gd`

## Overview

Skin-only subsurface scattering for imported character bodies and heads.
Preserves source PBR textures, tints and all existing character wet gear.
One shared material variant per source+quality. Never touch hair/eyes/cloth.
On Performance/Balanced/Compatibility, skip BOTH the skin shader variant
and the expensive screen-space SSS composite.

## Functions

### `settings`

```gdscript
static func settings(level: int, method: String) -> Dictionary
```

### `is_skin_mesh`

```gdscript
static func is_skin_mesh(mesh: MeshInstance3D) -> bool
```

Only explicit skin meshes, not _Body clothing, helmets, hair or robotic
fallback meshes. Artists can explicitly tag other skin nodes with "skin".

### `supports`

```gdscript
static func supports(material: StandardMaterial3D) -> bool
```

### `variant`

```gdscript
static func variant(source: StandardMaterial3D, level: int, method: String) -> StandardMaterial3D
```

The source is an untouched imported/tinted material. Duplicating shares
all original normal/ORM/albedo textures and avoids mutating sibling actors.

### `configure`

```gdscript
static func configure(level: int, method: String, scene_root: Node = null) -> void
```

Only change renderer-global kernel when the requested tier/backend changes.
New actors pick up current_level/current_method when their model is built.
Existing actors are updated on preset switches, NEVER on every frame.

### `clear_cache`

```gdscript
static func clear_cache() -> void
```

