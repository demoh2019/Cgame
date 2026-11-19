# Days After — Cgame playable prototype

A small **first-person survival vertical slice** developed alongside the Cgame
engine. This is a *new prototype*, not a complete version of the planned game.

## Play

Open `demo/days_after/project.godot` with a compiled Cgame editor, or run
`<path-to-cgame-binary> --path demo/days_after` from the Cgame repository root.

- WASD — move
- Mouse — look around
- Shift — sprint (drains stamina)
- Space — jump
- E — collect a supply box while looking at it from within 3 m
- 1 — eat food from the backpack
- 2 — drink water from the backpack
- Esc — release the mouse cursor; click to recapture

Food and water drain over time; starvation/dehydration reduces health. Use
pickups to replenish supplies. A 10-minute real-time day cycle changes the
lighting. The map includes static ruins and dynamic physics crates.

## Automated smoke test

With a compiled editor binary:

```sh
<path-to-cgame-binary> --headless --path demo/days_after --script res://smoke_test.gd
```

The smoke test checks survival resource draining, clamping, starvation damage,
scene loading, pickups and food consumption.

## Engine vs. game boundary

This version uses existing Cgame / Godot 4.8-compatible APIs:
`CharacterBody3D`, `RigidBody3D`, `PhysicsRayQueryParameters3D`, light
and environment nodes. No engine-level change is necessary for these mechanics.

Future Cgame changes should be driven by reproducible gaps found when building
Days After (for example, world streaming or large-scale destructible structures)
and should receive standalone regression tests in the engine.
