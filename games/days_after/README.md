# Days After — survival sandbox RPG prototype

An original 3D survival sandbox RPG developed on the **Cgame** Godot fork. It combines post-apocalyptic survival and exploration with gathering, crafting and equipment-driven progression. It uses no proprietary assets or code from its inspirations.

## Run

From the Cgame repository root:

```bash
godot --path games/days_after
godot --headless --path games/days_after --script res://smoke_test.gd
```

| Action | Controls |
|---|---|
| Move, look, sprint | WASD, mouse, Shift |
| Gather resources / pick up supplies | E (aim at object) |
| Attack infected | Left mouse (aim at enemy) |
| Consume food / water | 1 / 2 |
| Craft spear / coat / bandage | 3 / 4 / 5 |
| Equip spear / coat | 6 / 7 |
| Use bandage | 8 |
| Release / capture cursor | Esc / left mouse |
| Save / load local checkpoint | F5 / F9 |

## Playable gameplay loop

- Scavenge food, water and scrap in a greybox ruined zone.
- Harvest finite nodes of wood, fiber and stone to gain gathering XP.
- Craft a **makeshift spear** (2 wood + 1 scrap), **padded coat** (3 fiber + 2 scrap), and **bandage** (2 fiber).
- Equip a spear for 24 damage versus 6 bare-handed; a coat reduces incoming damage by 25%.
- Fight a pursuing infected, bandage wounds, and manage hunger, thirst and stamina.
- Gain crafting and gathering XP and see levels and equipment in the HUD.
- Crafting first checks all ingredients. Failed crafting does not consume anything.

## Persistent local world checkpoints

**F5** saves and **F9** restores a versioned offline JSON checkpoint in
`user://days_after_save_v1.json` (the engine's per-user application data
directory). The checkpoint includes health, hunger, thirst, stamina, inventory,
crafted gear, equipped combat style, gathering/crafting experience, player
position, collected supply pickups, remaining resource-node charges and
infected health/positions. Depleted resources and defeated infected stay
depleted after reloading; they are hidden and removed from collision queries,
rather than deleted from the scene.

Loading validates the schema, all item IDs and stack bounds, equipped item
ownership, XP and health ranges, resource-node capacities, enemy state and
finite world coordinates **before applying any state change**. Malformed,
truncated and outdated saves are rejected without mutating the running game.
Writing uses a temporary file and a rename to protect an existing checkpoint
against partial writes. This is local single-player persistence; editable
JSON files are **not trusted online player data**. A future authoritative
server must validate saves, trades, crafting and inventory ownership.

Run both regressions using a compiled Cgame/Godot 4 executable:

```bash
godot --headless --path games/days_after --script res://smoke_test.gd
godot --headless --path games/days_after --script res://smoke_test_save.gd
```

## Tests and engine architecture

Run the headless smoke test command above against a compiled **Cgame** build. It checks scene structure, inventory, finite node harvest, crafting atomicity, progression, gear, combat and survival. A checked-in smoke test **is not** a passed test until executed on the built engine.

Gameplay state stays in `survival_state.gd`. Game-specific nodes are in the game; physics, raycasting and collision use Cgame's existing native API. Only extend Cgame itself for general-purpose engine capabilities that are truly missing; test the native API separately, then integrate into the game.

## Next milestones (not implemented yet)

- Pathfinding AI, expanded weapons/abilities and NPC behavior.
- Procedural zones, world streaming, multiple checkpoint slots and save migrations.
- Dedicated server authority, multiplayer synchronization and anti-cheat.
- Safe and contested regions, loot rules, PvP, guilds and territories.
- Tiered professions, gear durability, player markets and settlements.
- More post-apocalyptic simulation: weather, infection, building, vehicles.
