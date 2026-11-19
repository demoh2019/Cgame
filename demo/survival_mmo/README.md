# Cgame survival x sandbox prototype

An original vertical slice combining post-apocalyptic survival with
player-driven sandbox progression. It uses **Cgame's existing 3D physics,
collisions, rendering and UI**. No source code or assets are copied from
Days After or Albion Online.

**Current scope: offline single-player.** Networking, guilds, territorial
PvP, economy and persistent online world are NOT implemented. Local JSON
persistence is for development only; it is not authoritative or anti-cheat.

## Run

Open `demo/survival_mmo/project.godot` in a compatible Cgame editor:

```sh
godot --path demo/survival_mmo
godot --headless --path demo/survival_mmo --script res://smoke_test.gd
godot --headless --path demo/survival_mmo --script res://save_test.gd
```

The headless scripts cover combat and crafting, progression, collision-checked
construction, and persistence snapshots including malformed/incompatible saves.
Successful test runs have not yet been verified on a Cgame executable.

## Gameplay

- WASD moves, Shift sprints; **E** gathers wood, stone, fiber or herbs.
- Logging, mining and foraging gain **5 XP per resource interaction**. Every
  20 XP increases the associated skill level (max 10). From level 3 onward,
  one collection action gives two items, consuming one resource-node charge.
- **Space** attacks the nearest infected. Combat XP: 3 per nonlethal hit, 20
  per kill. Combat level adds +2 melee damage per level. Infected drop scrap.
- **Q** crafts a starter spear for 2 wood and 1 stone (base damage 26).
- **T** upgrades the spear to a reinforced spear for 1 wood, 2 stone and 2
  scrap, after reaching combat level 2 (base damage 40). Weapon equip state
  determines damage; no fixed character class.
- **H** uses a bandage for 2 fiber and 1 herb (+35 health).
- **F** eats a herb to restore hunger.
- **B** builds a physical barricade for 3 wood and 2 stone. Physics-shape
  placement validation happens **before** resources are spent. Obstacles or
  characters prevent overlapping construction. Successful building grants
  10 crafting XP.
- **K** saves the character and world in `user://survival_world_v1.json`.
- **L** restores inventory, skills, health/hunger, weapon, position, depleted
  resource nodes, infected health/position and built barricades. Loading an
  invalid snapshot leaves the active world unchanged.
- **R** restarts the prototype without overwriting the last save.

The save format is JSON with an explicit schema version and bounded values;
saves are written via a temporary file and a previous-save backup. Interrupted
saves can recover from a valid `.bak` file. Local saves are user-editable:
**do not use them as client-authoritative data in an online MMO**. No autosave,
cloud saves, migrations or chunk/world streaming exists yet.

Crafting a weapon grants 12 crafting XP; using a bandage grants 8. This
prototype uses constant recipes and simple progression as balance placeholders.

## Engine vs. game ownership

The simulation rules in `game_state.gd` are separated from rendering,
input and scene creation in `main.gd`. The longer-term plan is authoritative
multiplayer (all crafting, inventory, combat, building and skill changes
validated by a server), persistent characters, world zones and player trade.

Only introduce C++ engine APIs after identifying a **reusable, measured engine
limitation**. The current mechanics are fully implementable through existing
Cgame/Godot gameplay primitives.

## Next milestones

1. Data-driven equipment inventory (durability, slots, tiers, weight).
2. Building previews, terrain checks, destruction and structural durability.
3. Server-authoritative protocol and durable database persistence.
4. Interest management, world partitioning, server-validated interactions.
5. PvP zones, guild structures, player economy and server load tests.
