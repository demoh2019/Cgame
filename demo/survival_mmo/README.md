# Cgame survival x sandbox prototype

This standalone gameplay vertical slice explores how **post-apocalyptic survival**
and **player-driven sandbox MMO progression** could share one game architecture.

It is an original placeholder prototype, **not** copied Days After or Albion
assets/code. The game is **offline single-player**: no multiplayer, account,
economy, guild or persistent-world service is implemented yet.

## Run

Open `demo/survival_mmo/project.godot` in a Cgame editor built from this
repository, or run it from the engine executable:

```sh
godot --path demo/survival_mmo
```

Headless smoke checks (state/recipes/gathering/combat/building):

```sh
godot --headless --path demo/survival_mmo --script res://smoke_test.gd
```

## Controls and game loop

- WASD move, Shift sprint, E gather a nearby object (wood/stone/fiber/herbs).
- Space attacks the nearest infected within melee range. Zombies pursue and
  attack the survivor; they drop scrap on defeat.
- Q crafts a spear from 2 wood + 1 stone, improving melee damage.
- H uses a bandage from 2 fiber + 1 herb to restore health.
- F eats a herb to relieve hunger.
- B consumes 3 wood + 2 stone to place a collision-enabled barricade.
- R restarts the prototype.

## Engine-vs-game ownership

The project uses **existing Cgame engine primitives** (CharacterBody3D,
StaticBody3D, physics collision shapes, scene tree, UI). No engine-level change
is needed for this first vertical slice. Keep rules in `game_state.gd` so a
future authoritative server can own inventory, combat, crafting and building.
Only add C++ engine APIs when a **measured, reusable** deficiency is found.

## Next checkpoints

1. Input actions/remapping, interaction prompts, proper loot entities.
2. Crafting stations, building placement validation, structural durability.
3. Data-driven equipment modifiers/progression, survival effects, enemy AI.
4. Server-authoritative state, persistence, client prediction/reconciliation.
5. World streaming/zone partitioning, trading, PvP rules and guild territories.
6. Performance profiling and stress tests before adding C++ engine capabilities.
