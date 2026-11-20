# Reactive NPC AI: native perception + behavior tree

A minimal playable Godot project using two native classes from this engine fork:
- `AIVisualSensor2D`: deterministic single-target vision (range, FOV, line-of-sight input, hysteresis and last-known-position memory).
- `BehaviorTree`: reactive priorities, condition guards, waits and blackboard actions.

There are no external assets or plugins. The 2D demo simulates one player and one enemy. The gray wall is a real `StaticBody2D` that blocks the ray query; the circles use simple scripted movement with wall collision. No navigation mesh or pathfinding is included.

## Run

Build this fork of Godot with the `behavior_tree` module enabled, then open `modules/behavior_tree/demo_reactive_ai/project.godot`, or launch from the repository root:

```sh
./bin/godot.linuxbsd.editor.x86_64 --path modules/behavior_tree/demo_reactive_ai
```

Move the blue player with **arrow keys**. Press **Space** to damage the nearby enemy or **R** to restart. Walk around the wall to enter the enemy's visible cone, then hide behind the wall to see it investigate your last known position. Damage the enemy to trigger emergency retreat.

## How the game uses the native engine APIs

Each AI tick (0.2 s), the demo uses `PhysicsDirectSpaceState2D.intersect_ray()` to check whether a wall blocks the segment between the enemy and player. It then calls:

```gdscript
sensor.observe(enemy_position, enemy_forward, player_position, _has_line_of_sight(), AI_TICK_SECONDS)
brain.set_blackboard_value("target_visible", sensor.is_target_visible())
brain.set_blackboard_value("target_remembered", sensor.has_target_memory())
brain.set_blackboard_value("last_known_position", sensor.get_last_known_position())
brain.tick()
```

The native sensor evaluates range/FOV and tracks memory. It does **not** query physics on its own; each game chooses which geometry or teams block vision. Sensor instances must not be shared between unrelated NPCs/targets.

### Behavior priorities

```text
reactive_selector
├── reactive_sequence
│   ├── low_health == true
│   ├── action = retreat
│   └── wait: 2 ticks
├── reactive_sequence
│   ├── target_visible == true
│   ├── action = chase
│   └── wait: 2 ticks
├── reactive_sequence
│   ├── target_remembered == true
│   ├── action = investigate
│   └── wait: 2 ticks
└── action = patrol
```

A `reactive_selector` reevaluates higher-priority branches each tick. A `reactive_sequence` rechecks guards during waits. The enemy therefore interrupts investigation to chase when a target becomes visible, and interrupts any lower-priority behavior to retreat when its health drops to 30 or less.

`AIVisualSensor2D` uses seconds for memory expiry; `BehaviorTree` `wait` uses whole logical ticks. The sensor's sight radius is 240 units, lose-sight radius 290 units, field of view 260 degrees, and memory is 2.5 seconds.

## Tests

C++ module regression tests live in:

- `modules/behavior_tree/tests/test_behavior_tree.h`
- `modules/behavior_tree/tests/test_ai_visual_sensor_2d.h`

Build and run the standard Godot test suite:

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --quit-after 20
```

The last command is a scene startup smoke check, not an interactive gameplay test.

## Scope

The scene lives inside the **engine fork** as a feature integration demo. It is not automatically incorporated into a separate game's repository. A real game can create one `AIVisualSensor2D` per NPC/target and pipe its output into a `BehaviorTree` blackboard and character movement controller. Follow-on systems could add hearing, multi-target tracking, teams, navigation around obstacles, perception events and AI debugging tools.
