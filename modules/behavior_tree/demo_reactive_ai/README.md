# Reactive NPC AI — Cgame develop integration

A self-contained 2D sandbox for this fork's **resource-backed** behavior-tree runtime plus its native sight and hearing sensors. This project is separate from the canonical *Albion After* game in `game/`; the engine functionality is also wired into that game's server infected AI through `native_infected_senses.gd`.

## Run

```sh
./bin/godot.linuxbsd.editor.x86_64 --path modules/behavior_tree/demo_reactive_ai
```

Move the blue survivor with **arrow keys**, press **F** to shout, **Space** near the infected to attack, **R** to restart. Movement emits quieter footsteps. The wall blocks sight and attenuates sound. The NPC follows paths around the wall, remembers the player's last visible position, and investigates the last heard sound.

The game uses:
- `BehaviorTreeRunner` (Node) with `BehaviorTreeReactiveSelector` and `BehaviorTreeReactiveSequence` (Resource tasks);
- `BehaviorTreeBlackboardCheck`, `BehaviorTreeBlackboardSet`, and `BehaviorTreeWait` (time-based waits);
- `AIVisualSensor2D`, `AIHearingSensor2D` (native reusable sensors);
- Godot `AStarGrid2D` with an inflated four-way grid for obstacle navigation;
- a `StaticBody2D` and `PhysicsRayQueryParameters2D` for line-of-sight.

**AI priorities**: retreat (low health) → chase (visible) → investigate last seen → investigate sound → patrol. The reactive selector rechecks higher priorities every AI tick. On any terminal result the demo resets the `BehaviorTreeRunner` before its next tick, because this API caches terminal status. Blackboard writes are applied by native `BehaviorTreeBlackboardSet` resources.

## Automatic tests

Build the fork with unit tests, then execute:

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --headless --test
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_demo.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/behavior_tree/demo_reactive_ai --script res://tests/smoke_navigation_hearing.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path game --script res://tests/run_all.gd
```

Native doctest cases: `modules/behavior_tree/tests/test_reactive_behavior_tree.h`, `test_ai_visual_sensor_2d.h`, `test_ai_hearing_sensor_2d.h`.

The Cgame native AI classes are **not** part of stock Godot. Running the standalone sandbox requires the fork's compiled binary. The canonical game's `native_infected_senses.gd` instead gracefully degrades to the existing GDScript hearing/sight logic when the custom native classes are unavailable.

## Limits

This demo has a static grid, one NPC, and one player. It is not a 3D navigation mesh, group steering, replicated server combat, or a substitute for the canonical game. For the main game, only already-authorized hearing and visual events enter the new native sensor memory; its existing server combat, safe-zone, wind, line-of-sight, scent and threat rules remain authoritative.
