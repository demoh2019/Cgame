# dungeon_occlusion.gd

> Conservative procedural occluders for the streamed underground wall kit.

`res://scripts/client/dungeon_occlusion.gd`

## Overview

Conservative procedural occluders for the streamed underground wall kit.
Like Unreal's precomputed visibility or Unity's static occluders, the blocking
geometry is deliberately simpler than the visible art. No collider or
authoritative dungeon layout is touched.

## Constants

- `const MIN_WALL_LENGTH := 2.0`
- `const MIN_WALL_HEIGHT := 0.65`
- `const INNER_WIDTH := 0.82`
- `const INNER_HEIGHT := 0.7`
- `const INNER_DEPTH := 0.55`

## Functions

### `use_occlusion`

```gdscript
static func use_occlusion(level: int, method: String, underground: bool) -> bool
```

The CPU occlusion solver is useful in a room maze, not in our open overworld.
Compatibility and low-end Performance do not pay for an additional CPU pass.

### `supports_wall`

```gdscript
static func supports_wall(bounds: AABB) -> bool
```

Reject small decorative meshes and non-wall-shaped bounds. Avoid culling
through doors and windows: callers pass only solid wall kit pieces.

### `inner_bounds`

```gdscript
static func inner_bounds(bounds: AABB) -> AABB
```

Shrink every axis so the software occluder stays safely inside the actual wall.
The reduced height also respects the top-down camera that looks over low walls.

### `add_wall`

```gdscript
static func add_wall(wall: Node3D) -> bool
```

Create only one cheap BoxOccluder3D within the largest solid mesh piece.
All transformations are expressed in the wall root's local space, which
handles GLTF child transforms and _kit's yaw, scaling and instancing.

### `update_viewport`

```gdscript
static func update_viewport(viewport: Viewport, level: int, method: String, underground: bool) -> void
```

A viewport property switch is cheap compared with rebuilding streamed chunks.
Don't set it every render frame if the underground state has not changed.

