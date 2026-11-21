# htn_planner.gd

> Hierarchical Task Network planner, in the style of the HTN planners used by Horizon Zero Dawn (Guerrilla) and Transformers: Fall of Cybertron.

`res://scripts/shared/htn_planner.gd`

## Overview

```text
Hierarchical Task Network planner, in the style of the HTN planners used
by Horizon Zero Dawn (Guerrilla) and Transformers: Fall of Cybertron.

Domain layout (plain data):
  compound task  -> Array of methods, tried in order:
                    {"preconditions": {key: value}, "subtasks": ["a", "b"]}
  primitive task -> {"preconditions": {key: value}, "effects": {key: value}}
A task is primitive when its entry is a Dictionary with an "effects" key.
Planning decomposes depth first, simulating effects on a copy of the world
state and backtracking to the next method when a branch dead-ends. Fully
deterministic: methods are tried in declaration order.
```

## Functions

### `plan`

```gdscript
static func plan(domain: Dictionary, root_task: String, state: Dictionary, max_steps: int = 256) -> Array[String]
```

Returns the primitive task names to execute, or an empty array when the
root task cannot be decomposed within `max_steps` expansions.

_2 private function(s) starting with `_` are not listed._
