# pcg_graph.gd

> Procedural content graph runtime (UE5 PCG-style): typed point-data graphs with subgraphs, an extension API, a dependency-aware incremental cache, a per-node ...

`res://scripts/shared/pcg_graph.gd`

## Overview

```text
Procedural content graph runtime (UE5 PCG-style): typed point-data graphs with
subgraphs, an extension API, a dependency-aware incremental cache, a per-node
debugger and per-world-partition-cell execution.

Original GDScript implementation. Design inspired by the publicly documented
concepts of Unreal Engine 5's PCG framework (typed pins, point data with
attributes, subgraphs, partitioned generation, debug capture). No Unreal code
was copied. The 64-bit integer mixer in mix64() is the public-domain
SplitMix64 finaliser (Sebastiano Vigna, CC0 / public domain).

DATA (all plain Dictionaries, tagged by "type"):
  points   {positions: PackedVector3Array, attrs: {density, scale, rotation_y: PackedFloat32Array,
            seed: PackedInt64Array, <custom>: PackedFloat32Array}}
  spline   {points: PackedVector3Array, closed: bool}
  volume   {aabb: AABB}
  landscape {height_at: Callable(x, z) -> float, normal_at: Callable(x, z) -> Vector3}
  mesh_instances  {records: [{mesh_id, transforms: Array[Transform3D]}]}
  scene_instances {records: [{scene_path, transforms: Array[Transform3D]}]}
  layer_weights   {layer, positions, weights}
Node outputs are cached and shared; nodes must never mutate their inputs.

PINS: a pin type string is one of the types above or "any". A trailing "[]"
on an INPUT pin type makes it multi-input (the node receives an Array).

EXTENSION: register_node(type, input_pins, output_pins, execute). The Callable
may take (inputs), (inputs, params) or (inputs, params, ctx) and must return a
Dictionary mapping output pin name -> data. ctx holds node_seed (int),
has_bounds (bool), bounds (AABB, partition cell) and node_id.
```

## Constants

- `const T_POINTS := "points"`
- `const T_SPLINE := "spline"`
- `const T_VOLUME := "volume"`
- `const T_LANDSCAPE := "landscape"`
- `const T_MESHES := "mesh_instances"`
- `const T_SCENES := "scene_instances"`
- `const T_LAYER := "layer_weights"`
- `const T_ANY := "any"`
- `const _BIG := 1.0e6`

## Documented variables

- `var executed_nodes: Array[String] = []` - Node ids that actually ran in the last execute()/partition_execute() (cache misses), in order.
- `var debug: Dictionary = {}` - node id -> {step, type, executed, usec, inputs, outputs, ...}
- `var debug_steps: Array[Dictionary] = []` - Same entries in dependency order, for step-by-step stepping.

## Functions

### `make_points`

```gdscript
static func make_points(positions: PackedVector3Array = PackedVector3Array()) -> Dictionary
```

### `make_spline`

```gdscript
static func make_spline(pts: PackedVector3Array, closed: bool = false) -> Dictionary
```

### `make_volume`

```gdscript
static func make_volume(box: AABB) -> Dictionary
```

### `make_landscape`

```gdscript
static func make_landscape(height_at: Callable, normal_at: Callable = Callable()) -> Dictionary
```

height_at(x, z) -> float; normal_at(x, z) -> Vector3 (derived by finite differences when omitted).

### `point_count`

```gdscript
static func point_count(d: Variant) -> int
```

### `landscape_height`

```gdscript
static func landscape_height(ls: Variant, x: float, z: float, fallback: float) -> float
```

### `landscape_normal`

```gdscript
static func landscape_normal(ls: Variant, x: float, z: float) -> Vector3
```

### `mix64`

```gdscript
static func mix64(x: int) -> int
```

### `hash3`

```gdscript
static func hash3(a: int, b: int, c: int) -> int
```

### `rand01`

```gdscript
static func rand01(h: int) -> float
```

### `register_node`

```gdscript
func register_node(type_name: String, input_pins: Dictionary, output_pins: Dictionary, execute_fn: Callable) -> void
```

### `add_node`

```gdscript
func add_node(id: String, type_name: String, params: Dictionary = {}) -> String
```

### `set_param`

```gdscript
func set_param(id: String, key: String, value: Variant) -> void
```

### `get_param`

```gdscript
func get_param(id: String, key: String, default_value: Variant = null) -> Variant
```

### `link`

```gdscript
func link(from_id: String, from_pin: String, to_id: String, to_pin: String) -> String
```

Adds an edge. Returns "" on success, otherwise the validation error (the edge is not added).

### `add_graph_input`

```gdscript
func add_graph_input(id: String, pin_name: String, pin_type: String) -> String
```

Graph inputs/outputs used when this graph is reused as a subgraph.

### `add_graph_output`

```gdscript
func add_graph_output(id: String, pin_name: String, pin_type: String) -> String
```

### `get_io_pins`

```gdscript
func get_io_pins(inputs: bool) -> Dictionary
```

### `pins_compatible`

```gdscript
static func pins_compatible(from_type: String, to_type: String) -> bool
```

### `validate`

```gdscript
func validate() -> Array[String]
```

### `clear_cache`

```gdscript
func clear_cache() -> void
```

### `structure_hash`

```gdscript
func structure_hash() -> int
```

Hash of the whole graph definition (nodes, params, edges, nested subgraphs).

### `execute`

```gdscript
func execute(inputs: Dictionary = {}) -> Dictionary
```

### `partition_execute`

```gdscript
func partition_execute(grid_cell: Vector2i, cell_size: float, inputs: Dictionary = {}, margin: float = 0.0) -> Dictionary
```

Runs the graph for one world-partition cell. Sampling is restricted to the cell
(grown by `margin` so neighbour-dependent nodes see context) and the outputs are
cropped to the exact cell, so the union of all cells equals an unpartitioned run.

### `run_scoped`

```gdscript
func run_scoped(inputs: Dictionary, scope: String, bounds_ctx: Dictionary, seed_value: int) -> Dictionary
```

### `node_output`

```gdscript
func node_output(id: String, pin: String = "out") -> Variant
```

### `summarize`

```gdscript
static func summarize(d: Variant, sample_n: int) -> Dictionary
```

_44 private function(s) starting with `_` are not listed._
