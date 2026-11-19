# Days After — playable survival slice

A standalone 3D prototype running directly on the Cgame engine. Open `demo/days_after/project.godot` in the Cgame editor or launch it with the built Cgame executable.

## First playable loop

- Explore a small abandoned checkpoint in first-person; collide with terrain and walls.
- Look at colored supply crates and press **E** to collect water, food and scrap.
- Watch health, hunger, thirst and inventory in the HUD.
- Press **1** to drink water and **2** to eat; hunger and thirst decrease over time.
- If a survival stat runs out, health starts dropping; health reaching zero ends the run.
- Harvest regenerating wood, fiber and scrap deposits to level up gathering (50 XP per level).
- Craft a pickaxe from wood and scrap; advanced ore requires both a pickaxe and gathering level 2.
- Craft bandages from fiber, apply them to heal when wounded, and craft reinforced vests from ore + scrap.
- Track gathering and crafting experience separately. This is a lightweight classless progression experiment, **not** a copy of Albion Online's exact mechanics or assets.

Controls: **WASD** move, **Shift** sprint, **Space** jump, **E** interact/gather, **1/2** consume water/food, **3** craft bandage, **4** craft pickaxe, **5** use bandage, **6** craft reinforced vest, **Esc** release/capture cursor.

## Survival/crafting economy

| Item | Source | Use |
| --- | --- | --- |
| Wood, fiber, scrap (tier 1) | 45-second respawning nodes | Crafting |
| Ore (tier 2) | Deposit; gathering Lv. 2 + pickaxe | Higher-tier crafting |
| Bandage | 2 fiber | Restore 25 HP |
| Pickaxe | 2 wood + 2 scrap | Unlock ore mining |
| Reinforced vest | 2 ore + 2 scrap | Craftable inventory item; equip/mitigation is future work |

The demo currently has no server-authoritative resource rules, persistence, durability, PvP, or real equipment bonuses.

## Running and testing

From the Cgame repository root (replace `godot` with the built Cgame binary path):

```bash
godot --path demo/days_after --editor
godot --headless --path demo/days_after --script res://tests/test_survival_state.gd
godot --headless --path demo/days_after --script res://tests/test_progression.gd
godot --headless --path demo/days_after --quit-after 30
```

The pure survival-state regression runs without graphics. The headless scene launch is a separate smoke test, not a claim that rendering or gameplay have been tested.

## Architecture

`survival_state.gd` contains game-specific health/inventory rules; `progression.gd` contains pure resource/recipe/XP logic. Both are independent of SceneTree. `player.gd` uses standard CharacterBody3D and RayCast3D. `main.gd` generates the prototype world, gathering nodes, pickups and HUD.

**Engine-first rule:** reusable missing functionality should be implemented in Cgame's engine or an engine-generic module, with matching tests; Days After should only contain game-specific rules. This slice currently uses engine APIs already present. No global engine settings or physics core are changed.

## Next steps

Implement save/load (versioned), data-driven item resources and inventory slots, crafted equipment bonuses/durability, enemy AI and combat, risk zones, server-authoritative interactions, gameplay audio, terrain streaming, and performance/CI checks against the custom Cgame binary.
