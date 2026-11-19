# Behavior Tree module (runtime MVP)

This optional, built-in Godot module provides the **runtime foundation** of a
behavior tree system for gameplay AI. It is not a visual graph editor yet.
When enabled, all resources are available in the scene inspector and in
GDScript. The module has no third-party runtime dependencies.

## Included resources

- `BehaviorTreeSequence`: run children in order, stop at the first failure,
  resume the running child without repeating previous actions.
- `BehaviorTreeSelector`: try alternative branches until one succeeds, resume
  a running branch.
- `BehaviorTreeInverter`: swap success and failure (preserve running).
- `BehaviorTreeBlackboardCheck`: compare a blackboard key with a value.
- `BehaviorTreeBlackboardSet`: set a blackboard key.
- `BehaviorTreeWait`: wait for a duration with runner-local state.
- `BehaviorTreeTask`: script-extensible base class.
- `BehaviorTreeRunner`: one instance per AI agent with an independent
  blackboard and execution memory; manual or automatic frame ticking.

## GDScript usage

Add a `BehaviorTreeRunner` node to a scene, then assign a
`BehaviorTreeSequence` resource to its `root_task` property. Add a
`BehaviorTreeWait`, `BehaviorTreeBlackboardCheck` and
`BehaviorTreeBlackboardSet` as child resources in the inspector.

You can also assemble the tree from script:

```gdscript
extends Node

@onready var ai: BehaviorTreeRunner = $BehaviorTreeRunner

func _ready() -> void:
    var sequence := BehaviorTreeSequence.new()
    var wait_task := BehaviorTreeWait.new()
    wait_task.duration = 0.2

    var set_task := BehaviorTreeBlackboardSet.new()
    set_task.key = "can_attack"
    set_task.value = true

    sequence.add_task(wait_task)
    sequence.add_task(set_task)
    ai.root_task = sequence
    ai.auto_tick = true
```

To create a custom scripted behavior task:

```gdscript
extends BehaviorTreeTask

func _tick(blackboard: Dictionary, delta: float) -> int:
    if not blackboard.get("target_visible", false):
        return FAILURE
    # Perform or schedule a custom action here.
    return SUCCESS
```

`_tick` must return `SUCCESS`, `FAILURE`, or `RUNNING`. A runner stops
on completion and emits `tree_finished(status)` once. Call `reset()` to
repeat the tree; the blackboard remains intact. An unassigned root returns
`FAILURE` but does not permanently finish the runner.

## Concurrency and determinism

A single task resource can be shared by multiple agents or used multiple
times in one tree. Each `BehaviorTreeRunner` stores its own execution
cursors, and each occurrence of a task has its own position-based state.
Only user-supplied blackboard data is mutable across scripts; do not store
agent state on shared task resources.

Cycles in the built-in task graph are rejected. Each task executes
synchronously for a single tick and must not block the main thread. For
long-running work, return `RUNNING` and poll completion on later ticks.

## Tests

Build Godot with the module enabled and the standard test suite:

```shell
scons platform=linuxbsd target=editor dev_build=yes tests=yes module_behavior_tree_enabled=yes
bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="*[BehaviorTree]*"
```

These tests cover execution order, short-circuiting, running/resumption,
blackboard data, nested composites, cyclic-graph protection, multiple
agents, signals, automatic ticking, and resource serialization.

## Planned extensions

The runtime provides a foundation for a **graph editor** (the requested
editor experience), more leaf tasks, AI perception, asynchronous actions,
debug visualization, and StateTree-style hierarchy. Those are not
implemented by this first PR.
