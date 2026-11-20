# Reactive NPC AI: sight, hearing and A* navigation

This is a playable Godot demo bundled with the `Cgame` engine fork. It integrates three reusable native AI classes or engine systems:

- `BehaviorTree` — reactive sequence/selector, conditions, blackboard and logical-tick waits.
- `AIVisualSensor2D` — FOV, acquisition and loss radii, caller-provided LOS, last-seen-position memory.
- `AIHearingSensor2D` — explicit sound events with loudness, range, attenuation through walls, and memory in seconds.
- `AStarGrid2D` (built into Godot) — pathfinding around an inflated wall, used for chasing, investigating a seen target and investigating a sound.

The obstacle is a real `StaticBody2D`, used for raycast-based sight occlusion. The characters are lightweight procedural circles controlled by this game script; they are not full `CharacterBody2D` actors, and collision against the demonstration wall is resolved separately.

## Launch and controls

Open `modules/behavior_tree/demo_reactive_ai/project.godot` in a compiled editor of this fork, or start the project from the repository root:

```sh
./bin/godot.linuxbsd.editor.x86_64 --path modules/behavior_tree/demo_reactive_ai
```

**Arrow keys** move the blue player. Moving emits quiet footsteps every 0.7 seconds. **F** emits a loud shout from the player's position, including while hidden behind the wall. **Space** attacks the enemy when close. **R** resets the encounter.

### Behavior priorities

```text
reactive_selector
├── low_health == true       → retreat
├── target_visible == true   → chase using A*
├── target_remembered == true → investigate last seen position using A*
├── sound_remembered == true → investigate last heard position using A*
└── patrol
```

Each guarded branch is a `reactive_sequence`, which rechecks the guard during its wait. Vision interrupts sound investigation; low health interrupts all other decisions. The NPC's A* route is shown as a green line. The yellow X marks the last seen position. A cyan ring marks heard sound memory, and a transient expanding pulse shows emitted noise.

## Engine and game integration

The demo obtains LOS from a Godot physics ray cast. The C++ visual sensor accepts the Boolean LOS result; it never queries the scene tree on its own. To report a noise, game code calls:

```gdscript
var attenuation := 0.8 if not _has_line_of_sight() else 1.0
hearing.report_noise(enemy_position, player_position, 1.0, attenuation)
```

The game is responsible for emitting events: audio playback alone does not create an AI stimulus. In this demo, walls attenuate sound rather than blocking it completely. Each AI tick, the game advances sound memory and updates the BehaviorTree blackboard:

```gdscript
hearing.advance_time(AI_TICK_SECONDS)
brain.set_blackboard_value("target_visible", sensor.is_target_visible())
brain.set_blackboard_value("target_remembered", sensor.has_target_memory())
brain.set_blackboard_value("sound_remembered", hearing.has_sound_memory())
brain.set_blackboard_value("last_heard_position", hearing.get_last_heard_position())
brain.tick()
```

The sample grid has 24-pixel cells, blocks cells whose centers overlap an enemy-radius-inflated obstacle, and uses four-directional A* without diagonal corner cutting. Paths update when the requested goal cell or AI action changes; this is an example for a static obstacle, **not** a navigation-mesh bake, crowd avoidance, HLOD streaming, or a full navigation engine replacement.

## Build and test

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_demo.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_navigation_hearing.gd
```

Native C++ tests are in:
- `modules/behavior_tree/tests/test_behavior_tree.h`
- `modules/behavior_tree/tests/test_ai_visual_sensor_2d.h`
- `modules/behavior_tree/tests/test_ai_hearing_sensor_2d.h`

The two headless GDScript tests cover sight, occlusion, target memory, hearing events, pathfinding around the wall, reactive priorities, and resets. They are checked into the repo, but should be executed with **this fork's compiled binary**, not stock Godot (which lacks the new AI classes).

## Architecture notes

- One visual sensor and hearing sensor per NPC; the demo uses one target/listener pair. Implementing centralized noise broadcasts, hearing multiple emitters, teams, occlusion using physics material, 3D senses, and replicated multiplayer perception are separate future features.
- AI sensing is evaluated at fixed logical intervals. Noise is emitted by gameplay code in the physics step.
- Hearing duration and sight memory are specified in seconds; behavior-tree wait durations are specified in AI ticks.
- This scene is an engine-repository **integration demo**. An unrelated game repository must explicitly import/use these APIs and is not modified by this change.
