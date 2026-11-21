# goap_planner.gd

> Goal-Oriented Action Planning, as popularised by F.E.A.R.

`res://scripts/shared/goap_planner.gd`

## Overview

Goal-Oriented Action Planning, as popularised by F.E.A.R. (Jeff Orkin) and
reused in Tomb Raider, Deus Ex: Human Revolution and many Unity/Unreal AI
plugins. A* searches over world states: each action has a cost,
preconditions and effects (all key -> value Dictionaries). The heuristic is
the number of unsatisfied goal keys (scaled by the cheapest action cost so
it stays a lower bound for unit-ish costs). Ties resolve by insertion order,
so results are deterministic.

## Functions

### `plan`

```gdscript
static func plan(actions: Array, state: Dictionary, goal: Dictionary, max_nodes: int = 2048) -> Array[String]
```

Returns the action names of the cheapest plan reaching `goal`, or an empty
array when it is unreachable or `max_nodes` expansions are exhausted.

_3 private function(s) starting with `_` are not listed._
