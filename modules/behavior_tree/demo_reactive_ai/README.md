# Reactive BehaviorTree AI sandbox

A minimal playable Godot project using this engine fork's native `BehaviorTree` class. The scenario is a player and an NPC on a 2D field. The NPC patrols, pursues a nearby player, and retreats when injured. No imported assets or plugins are needed.

## Run

Build this Godot fork with the `behavior_tree` module enabled, then open `modules/behavior_tree/demo_reactive_ai/project.godot` in its editor, or launch it from a terminal:

```sh
./bin/godot.linuxbsd.editor.x86_64 --path modules/behavior_tree/demo_reactive_ai
```

Use **arrow keys** to move the blue player, **Space** to damage the red NPC when close, and **R** to reset.

## Native AI feature integration

The demo builds this tree using native nodes:

```text
reactive_selector
├── reactive_sequence
│   ├── condition: low_health == true
│   ├── wait: 2 ticks
│   └── set: action = retreat
├── reactive_sequence
│   ├── condition: player_visible == true
│   ├── wait: 2 ticks
│   └── set: action = chase
└── set: action = patrol
```

Unlike the existing memory-based selector/sequence, reactive composites revisit higher-priority conditions every tick. If health becomes low while the pursuit branch is running, retreat preempts it; the abandoned wait state is cleared. If visibility is lost, a pursuit wait is canceled instead of eventually executing an attack. The `wait` unit is **AI ticks** (here, 0.2 seconds each), not wall-clock seconds.

To compare with the previous behavior, change the two composite types in `main.gd` to `selector` and `sequence`, rebuild/restart and observe that conditions can remain stale while a wait is RUNNING.

This is an integration demo bundled with the engine fork, not a substitute for importing the AI into a separate game repository. For real gameplay, instantiate a `BehaviorTree` per NPC, set its blackboard keys from perception/health systems, and apply the resulting action to the actor controller.
