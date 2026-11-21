# state_tree.gd

> Hierarchical StateTree runtime in the spirit of Unreal Engine 5's StateTree (states with enter conditions, tasks, evaluators, prioritised transitions, linked...

`res://scripts/shared/state_tree.gd`

## Overview

```text
Hierarchical StateTree runtime in the spirit of Unreal Engine 5's StateTree
(states with enter conditions, tasks, evaluators, prioritised transitions,
linked subtrees). Original GDScript implementation written from the public
concept description; no third-party source code was copied. Callables are
registered by name so assets stay plain data (a whitelist).

Asset dictionary:
  {"name": String, "root": String,
   "evaluators": [String | {"fn": String, "args": Dictionary}],
   "states": {id: {"children": [id], "conditions": [cond], "tasks": [task],
                   "link": subtree_name,
                   "transitions": [{"trigger": "on_completed"|"on_failed"|"on_tick"|"on_event",
                                    "event": String, "condition": cond,
                                    "target": id | "$succeeded" | "$failed",
                                    "priority": int}]}}}
cond: String (registered condition), {"fn","args","not"}, {"key","op","value"}
      (built-in context compare) or an Array of conds that must all pass.
task: String or {"fn","args"}. A state without tasks never completes by itself.
Selection: from the root, the first child (depth-first) whose enter conditions
pass; a state with children but no selectable child is not selectable.
```

## Constants

- `enum Status { RUNNING, SUCCEEDED, FAILED }`
- `const TRIGGERS: PackedStringArray = ["on_completed", "on_failed", "on_tick", "on_event"]`
- `const MAX_LINK_DEPTH := 8`
- `const END_SUCCEEDED := "$succeeded"`
- `const END_FAILED := "$failed"`

## Documented variables

- `var trace: Array[String] = []` - Optional trace of enter/exit calls ("enter:id" / "exit:id") for debugging and tests.

## Functions

### `register_task`

```gdscript
func register_task(task_name: String, enter: Callable = Callable(), tick: Callable = Callable(), exit: Callable = Callable()) -> void
```

Registers a task. Callables are optional: enter(ctx, params), tick(ctx, dt, params) -> Status, exit(ctx, params).

### `register_condition`

```gdscript
func register_condition(cond_name: String, fn: Callable) -> void
```

cond Callable: (ctx: Dictionary, args: Dictionary) -> bool

### `register_evaluator`

```gdscript
func register_evaluator(eval_name: String, fn: Callable) -> void
```

Evaluator Callable: (ctx: Dictionary, dt: float, args: Dictionary) -> Dictionary (merged into ctx) or null.

### `register_subtree`

```gdscript
func register_subtree(subtree_name: String, asset: Dictionary) -> void
```

### `validate`

```gdscript
func validate(asset: Dictionary) -> Array[String]
```

Validates an asset against registered names. Returns a list of error strings (empty = ok).

### `set_asset`

```gdscript
func set_asset(asset: Dictionary) -> bool
```

Validates, flattens linked subtrees and installs the asset. False on error (see `errors`).

### `start`

```gdscript
func start(context: Dictionary) -> bool
```

### `stop`

```gdscript
func stop(context: Dictionary) -> void
```

### `send_event`

```gdscript
func send_event(event_name: String, payload: Variant = null) -> void
```

### `tick`

```gdscript
func tick(dt: float, context: Dictionary) -> int
```

### `debug_path`

```gdscript
func debug_path() -> String
```

### `current_state`

```gdscript
func current_state() -> String
```

### `is_active`

```gdscript
func is_active(state_id: String) -> bool
```

_17 private function(s) starting with `_` are not listed._
