# Days After — first playable slice

A self-contained survival game prototype for the Cgame Godot 4.8 fork.
It is a **game** rather than a benchmark: players explore a small 3D ruin,
collect food/water, and use supplies before hunger and thirst deplete health.

## How to launch

Open `demo/days_after/project.godot` using a compiled Cgame editor, then run
the main scene. Alternatively use a Cgame editor executable:

```sh
./bin/godot.linuxbsd.editor.x86_64 --path demo/days_after --editor
```

The scene uses only built-in Godot 4.8 nodes and materials. No external assets
or third-party plugins are required.

## Controls

| Input | Action |
| --- | --- |
| WASD | Move |
| Shift | Sprint |
| Space | Jump |
| Mouse | Look |
| E | Pick up a crate while aiming at it |
| 1 | Eat one collected food item |
| 2 | Drink one collected water item |
| F | Build a campfire from 3 wood T1 and 2 stone T1 |
| Esc | Release pointer |
| Left mouse button | Capture pointer |
| R | Restart the scene |

The HUD shows health, hunger, thirst, stamina, in-game time, inventory and a contextual hint.
Food restores 35 hunger points; water restores 45 thirst points. Depletion
reduces health. Sprinting drains stamina and walking recovers it. Gatherable
wood, stone and fiber support progression; campfires emit OmniLight3D light.
One full day lasts four real minutes. Pickups cannot be collected twice.

## Smoke test

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test.gd
```

The test verifies scene instantiation, collision ground, one-time scavenging,
inventory consumption, stat recovery and finite player position over 10 frames.

## Engine / game ownership

- **Cgame engine**: reusable physics, rendering, streaming, AI/nav, world tooling and
  other generalized platform capabilities, implemented natively when required.
- **Days After game**: survival rules, inventory, crafting, quests, enemies, levels,
  player controls, balance and presentation.
- Add engine features only after documenting a concrete missing capability,
  providing a focused native test, and exercising the feature in Days After.
- This first slice required **no engine changes**; it uses existing CharacterBody3D,
  StaticBody3D, Area3D, RayCast3D and UI features.

## Next vertical slices

1. Persistent inventory, equipment and saving/loading.
2. Zombie AI using navigation and combat with damage.
3. Crafting, looting containers and resource progression.
4. A larger streaming map with optimized collision and profiling.

This is a foundation for iteration, **not** a complete survival game.
