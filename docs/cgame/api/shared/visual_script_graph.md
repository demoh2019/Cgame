# visual_script_graph.gd

> Blueprint-style visual script runtime: event graph with execution pins and data pins, for gameplay logic, gameplay state graphs and RPC graphs.

`res://scripts/shared/visual_script_graph.gd`

## Overview

```text
Blueprint-style visual script runtime: event graph with execution pins and
data pins, for gameplay logic, gameplay state graphs and RPC graphs.

Design credit (concepts only, no code copied): the exec-pin / data-pin split and
pull-evaluated pure nodes follow the general dataflow model described for Unreal
Blueprints (Epic documentation, concepts are not copyrightable); the typed-node
sequence/branch/loop/event vocabulary follows Godot 3 VisualScript design notes
(Godot Engine, MIT licence); flow-based programming is J. P. Morrison's public
model. Implementation is original GDScript. No Apache-2.0/GPL/LGPL code ported.

Asset format:
  {"variables": {name: initial}, "machines": {name: {"initial": state}},
   "nodes": {id: {"type": ..., ...}},
   "exec": [[from_id, from_pin, to_id]],
   "data": [[from_id, from_out, to_id, to_in]]}

Node types and pins:
  event            "event": name, "outputs": [payload keys]; exec out "out"; data outs = payload keys
  branch           in "cond"; exec "true" / "false"
  sequence         "count": n; exec "0".."n-1"
  for_loop         ins "first","last" (inclusive), "max_iter"; exec "body","done"; data out "index"
  while            in "cond", "max_iter"; exec "body","done"
  set_var          "var"; in "value"; exec "out"
  get_var          "var"; data out "value"
  literal          "value", optional "value_type": int|float|string|bool; data out "value"
  math             "op": add sub mul div min max clamp compare and or not, "cmp" for compare;
                   ins "a","b","c"; data out "result"
  call             "fn": whitelisted host function, "args": n; ins "arg0".."argN"; out "result"
  delay            in "seconds"; exec "out" fires from tick(delta)
  print            in "text"; exec "out"
  emit_rpc         "rpc": name, "args": n; ins "arg0".."argN"; records into the outbox only
  state_enter      "machine","state"; exec "out"
  state_transition "machine","from" ("*" = any),"to"; exec "out" / "blocked"
  get_state        "machine"; data out "state"
Unlinked data inputs read constants from the node's "in" dictionary.
```

## Constants

- `const NODE_TYPES: Array[String] = [`
- `const PURE_TYPES: Array[String] = ["get_var", "literal", "math", "get_state"]`
- `const MATH_OPS: Array[String] = ["add", "sub", "mul", "div", "min", "max", "clamp", "compare", "and", "or", "not"]`
- `const CMP_OPS: Array[String] = ["==", "!=", "<", "<=", ">", ">="]`
- `const LOOP_TYPES: Array[String] = ["for_loop", "while", "delay"]`
- `const DEFAULT_LOOP_GUARD := 1000`
- `const MAX_DEPTH := 64`
- `const MAX_LOG := 1000`
- `const MAX_ERRORS := 100`

## Documented variables

- `var instruction_budget: int = 10000` - Instruction budget per fire() / delay continuation; stops runaway graphs.
- `var break_handler: Callable = Callable()` - Optional debugger hook: called as break_handler.call(node_id) when a breakpoint node runs.

## Functions

### `register_function`

```gdscript
func register_function(fn_name: String, callable: Callable, argc: int) -> String
```

Registers a host function. argc must match the callable's argument count (-1 skips the check).
Returns an error string, or "" on success.

### `unregister_function`

```gdscript
func unregister_function(fn_name: String) -> void
```

### `has_function`

```gdscript
func has_function(fn_name: String) -> bool
```

### `load_graph`

```gdscript
func load_graph(asset: Dictionary) -> Array[String]
```

### `is_loaded`

```gdscript
func is_loaded() -> bool
```

### `validate`

```gdscript
func validate(asset: Dictionary) -> Array[String]
```

### `get_var`

```gdscript
func get_var(var_name: String, default_value: Variant = null) -> Variant
```

### `set_var`

```gdscript
func set_var(var_name: String, value: Variant) -> void
```

### `get_state`

```gdscript
func get_state(machine: String) -> String
```

### `pending_count`

```gdscript
func pending_count() -> int
```

### `drain_outbox`

```gdscript
func drain_outbox() -> Array[Dictionary]
```

Returns and clears the outgoing RPC requests. The host decides how to send them.

### `to_dict`

```gdscript
func to_dict() -> Dictionary
```

### `set_breakpoint`

```gdscript
func set_breakpoint(node_id: String, enabled: bool = true) -> void
```

### `clear_trace`

```gdscript
func clear_trace() -> void
```

### `fire`

```gdscript
func fire(event_name: String, payload: Dictionary = {}) -> int
```

Runs every event node named event_name. Returns the number of handlers run.

### `tick`

```gdscript
func tick(delta: float) -> void
```

Advances delay nodes; due continuations run with a fresh instruction budget.

_27 private function(s) starting with `_` are not listed._
