# mass_entity.gd

> MassEntity-style data-oriented runtime: archetypes, structure-of-arrays fragments, processors with dependency ordering and optional parallel chunk execution.

`res://scripts/shared/mass_entity.gd`

## Overview

MassEntity-style data-oriented runtime: archetypes, structure-of-arrays fragments,
processors with dependency ordering and optional parallel chunk execution.

Design reference (concepts only, no code copied): Unreal Engine MassEntity
https://dev.epicgames.com/documentation/en-us/unreal-engine/mass-entity-in-unreal-engine
and the generic archetype ECS pattern (Unity DOTS / flecs, MIT) https://github.com/SanderMertens/flecs
Implementation: original GDScript written for this project, MIT-compatible.

## Constants

- `const INDEX_BITS := 24`
- `const INDEX_MASK := (1 << INDEX_BITS) - 1`

## Documented variables

- `var _fragment_types: Dictionary = {}` - fragment name -> Variant.Type (TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY)
- `var _archetype_lookup: Dictionary = {}` - archetype key -> index into _archetypes

## Functions

### `define_fragment`

```gdscript
func define_fragment(name: String, type: int) -> void
```

### `entity_count`

```gdscript
func entity_count() -> int
```

### `archetype_count`

```gdscript
func archetype_count() -> int
```

### `create`

```gdscript
func create(fragments: Dictionary) -> int
```

### `is_alive`

```gdscript
func is_alive(id: int) -> bool
```

### `destroy`

```gdscript
func destroy(id: int) -> void
```

### `has_fragment`

```gdscript
func has_fragment(id: int, fragment: String) -> bool
```

### `get_value`

```gdscript
func get_value(id: int, fragment: String) -> Variant
```

### `set_value`

```gdscript
func set_value(id: int, fragment: String, v: Variant) -> void
```

### `query`

```gdscript
func query(required: PackedStringArray) -> Array
```

Archetype chunks holding every required fragment. A chunk is a Dictionary of
packed arrays by fragment name plus "_ids" (slot per row) and "_count".
Write through chunk[name][i] = v to mutate in place.

### `add_processor`

```gdscript
func add_processor(name: String, required: PackedStringArray, callable: Callable, depends_on: PackedStringArray = PackedStringArray(), parallel: bool = false) -> void
```

### `remove_processor`

```gdscript
func remove_processor(name: String) -> void
```

### `processor_order`

```gdscript
func processor_order() -> PackedStringArray
```

Processor names in execution order (Kahn topological sort, stable by registration).

### `run`

```gdscript
func run(delta: float) -> void
```

_5 private function(s) starting with `_` are not listed._
