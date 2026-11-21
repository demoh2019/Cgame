# engine_features.gd

> (no header comment)

`res://scripts/client/engine_features.gd`

## Constants

- `const GameplayCues = preload("res://scripts/client/gameplay_cues.gd")`

## Functions

### `has`

```gdscript
static func has(engine_class: String) -> bool
```

### `tag_node`

```gdscript
static func tag_node(node: Node, tags: Array) -> void
```

Tags a node with Gameplay Tags (meta "tags") when the engine provides GameplayTagContainer; a no-op otherwise.

### `make`

```gdscript
static func make(engine_class: String, props: Dictionary = {}) -> Object
```

Creates an engine class by name and applies properties; returns null when the binary lacks it.

### `radial_push`

```gdscript
static func radial_push(parent: Node, at: Vector3, radius: float, strength: float, upward: float = 0.4, mask: int = 1 << 19, wall_mask: int = 0, wall_attenuation: float = 0.25, velocity_change: bool = false, falloff_mode: int = 1) -> bool
```

Radial physics push (RadialForceField3D) around a world position; false when the class is missing.
Bodies on the ragdoll layer (1 << 19) are pushed by default.

### `runtime_tags`

```gdscript
static func runtime_tags(kind: String, state: Dictionary) -> PackedStringArray
```

The native engine owns the live tag container. Snapshot states are read-only
hints for visuals/tools; server combat authority is never inferred from tags.

### `sync_runtime_tags`

```gdscript
static func sync_runtime_tags(node: Node, kind: String, snapshot: Dictionary) -> void
```

Replaces one namespace atomically, preserving static Enemy/Player identity.
Old engine binaries simply retain the established rendering paths.

### `runtime_effect_snapshot`

```gdscript
static func runtime_effect_snapshot(kind: String, snapshot: Dictionary) -> Dictionary
```

Presentation-only stack counts. The server remains authoritative for combat.
Falls back to the validated snapshot on stock Godot/older engine builds.
Render-side durations from the authoritative zombie snapshot.

### `tick_runtime_effects`

```gdscript
static func tick_runtime_effects(node: Node, delta: float) -> Dictionary
```

### `runtime_effect_remaining`

```gdscript
static func runtime_effect_remaining(node: Node, tag: String, fallback: float = 0.0) -> float
```

### `runtime_attribute_snapshot`

```gdscript
static func runtime_attribute_snapshot(kind: String, state: Dictionary) -> Dictionary
```

Derive read-only client attributes from the server-owned actor snapshot.
Effect sources are replaced atomically, so expired modifiers cannot persist.

### `runtime_attribute_value`

```gdscript
static func runtime_attribute_value(node: Node, name: String, fallback: float = 0.0) -> float
```

### `runtime_stack_count`

```gdscript
static func runtime_stack_count(node: Node, tag: String, fallback: int = 0) -> int
```

### `runtime_has`

```gdscript
static func runtime_has(node: Node, tag: String, fallback: bool = false) -> bool
```

### `runtime_has_resolve`

```gdscript
static func runtime_has_resolve(node: Node, fallback_stacks: int = 0) -> bool
```

Resolve visual gate: two or more Resolve stacks (native threshold query when available).

### `hit_feedback_strength`

```gdscript
static func hit_feedback_strength(node: Node, base_strength: float) -> float
```

Cosmetic only: stackable native hit feedback for rapid consecutive hits.
The Local.Visual namespace is never authoritative gameplay state.

