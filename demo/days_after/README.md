# Days After — survival, crafting and classless progression

A standalone, playable **prototype** in the Cgame Godot 4.8 fork.
The project merges two complementary gameplay pillars:

1. **Post-disaster survival** — explore ruins, find food and water, manage
   hunger/thirst/health, and treat wounds.
2. **Equipment-driven sandbox progression** — harvest tiered materials,
   level gathering by using it, and craft gear that unlocks new opportunities.
   There are no fixed character classes.

The inspiration is the genre design of *Days After* and *Albion Online*; all
prototype code, scenery and mechanics here are newly implemented for Cgame.
No third-party game assets or proprietary source code are included.

## Run

Open `demo/days_after/project.godot` using a compiled Cgame editor and press
Play. From the repository root on Linux:

```sh
./bin/godot.linuxbsd.editor.x86_64 --path demo/days_after --editor
```

The scene is generated from built-in Cgame/Godot 4.8 primitives and needs no
external assets.

## Controls

| Key | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Shift / Space | Sprint / jump |
| E | Pick up supplies or harvest a deposit under the crosshair |
| 1 / 2 | Eat / drink from inventory |
| 3 | Craft field bandage from two T1 fibers |
| 4 | Craft and automatically equip scavenger tool (two T1 wood, one T1 stone) |
| 5 | Use field bandage (+30 health) |
| 6 | Craft reinforced bandage (two T2 fibers, one T1 fiber) |
| 7 | Use reinforced bandage (+60 health) |
| Esc / left click | Release / recapture pointer |
| R | Restart (this demo does not save progress yet) |

The HUD displays survival stats, stored resources, equipment, fiber gathering
level, crafting experience, and the most recent action/failure reason.

## First progression loop

1. Find **food and water** so hunger/thirst do not kill the survivor.
2. Harvest **two T1 fabric deposits** (2 fiber each). Each successful gathered
   unit yields 25 gathering XP per tier; after 60 fiber XP the player reaches
   fiber level 2. A deposit can be harvested only once.
3. Harvest **wood T1 x2** and **stone T1 x1** to craft and equip the scavenger tool.
4. With fiber level 2 **and** the tool equipped, harvest **fiber T2**.
   Failed interactions never consume or deplete resource deposits.
5. Craft basic or advanced bandages to regain health while managing supplies.
   All recipes are atomic: if any ingredient is missing, no material is spent.

Only two resource tiers are implemented so far, even though the resource node
exposes a wider editor range. Additional tiers need balancing and more
equipment/progression rules.

## Smoke test

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test.gd
```

Covers scene instantiation, physical world, one-use pickups, survival
consumption, tier/gear/XP gates, non-duplicating harvest, atomic crafting,
healing, experience rewards and finite position over 10 physics frames.

## Engine vs game ownership

- **Cgame engine:** reusable physics, destruction, fluids, rendering, navigation,
  streaming, networking and performance systems; extend native code when the
  game demonstrates an unmet requirement, with regression tests.
- **Days After game:** survival, resource/equipment tiers, recipes, progression,
  enemies, zones, economy, loot, combat balance and user experience.
- **Current vertical slice:** no new engine API is needed; it uses
  CharacterBody3D, StaticBody3D, Area3D, RayCast3D and built-in UI.

## Next slices

1. Data-driven item/equipment definitions with save/load and proper inventory UI.
2. Zombie threats and damage, with classless combat skills selected by gear.
3. Resource respawns, multiple risk zones and clear PvE/PvP rules.
4. Player settlements, crafting stations, trading/economy and network sync.
5. Chunk streaming, navigation under load, profiling and stress tests.

This is a technical foundation, **not** an entire survival/MMO release.
