# Days After × Albion — Cgame survival sandbox prototype

A standalone **first-person post-apocalyptic sandbox** combining survival
mechanics with classless gathering/crafting progression. This is an original
prototype, not a reproduction of either game's content or assets.

## Run

Open `demo/days_after/project.godot` using a Cgame editor build, or execute:

```sh
<cgame-editor> --path demo/days_after
```

- WASD / mouse — move and look, Shift sprint, Space jump, Esc release cursor
- E — collect supplies or gather from resource nodes within 3 m
- 1 / 2 — eat / drink supplies
- 3 / 7 — use bandage / medkit to restore health
- 4 — craft bandage (2 fiber), grants 20 crafting XP
- 5 — craft hatchet (2 wood + 2 scrap), grants 25 crafting XP
- 6 — craft medkit (3 fiber + 1 scrap), requires crafting level 2

Gather wood, fiber and scrap in the ruins. Each node has three charges and
awards 12 gathering XP per charge. A crafted hatchet increases **wood** yield,
making equipment affect what you can do instead of locking you to a class.
Each 40 skill XP grants a new level. Crafting validates all requirements before
consuming any materials; failed crafts never cost resources.

Survival drains food/water and sprint stamina. Starvation or dehydration harms
health. Ten real-world minutes represent an in-game day. Environmental ruins
include rigid-body crates affected by the native Cgame physics engine.

## Automated smoke test

```sh
<cgame-editor> --headless --path demo/days_after --script res://smoke_test.gd
```

The test covers needs, starvation, recipe gating/atomicity, XP levels, scene
startup, one-time supply pickup, finite resource nodes, equipment gathering
bonuses, healing and food consumption.

## Engine / game ownership

Currently all mechanics use stable Godot/Cgame engine APIs. Game-specific
state lives in `survival_state.gd` and `progression.gd`; interactive
resources are in `resource_node.gd`. No speculative engine modification
is required. Move capabilities into Cgame's engine layer only when an actual
reusable gap is demonstrated and covered by regression tests.

Next steps: server-authoritative inventory, crafting stations, durability,
territories, zombies, cooperative networking and persistence.
