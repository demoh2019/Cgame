# Days After — Survival Sandbox (Cgame)

An original post-apocalyptic survival sandbox made with the Cgame Godot 4.8
fork. One **playable game** combines survival/scavenging with classless
gathering, professions, tiered resources, and crafting. No external art is
required for this prototype.

## Play

Open `demo/days_after/project.godot` in a compiled Cgame editor or run:

```sh
./bin/godot.linuxbsd.editor.x86_64 --path demo/days_after --editor
```

Movement is first-person and the environment uses real colliders. Explore the
ruins to find supply crates and renewable-in-future resource deposits. The
current finite deposits are removed after a successful harvest.

| Key | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Shift / Space | Sprint / jump |
| E | Pick up supplies or harvest aimed resource |
| 1 / 2 | Eat / drink a collected item |
| 3 | Craft field bandage (2 fiber T1) |
| 4 | Craft scavenger tool (2 wood T1, 1 stone T1); auto-equips |
| 5 | Use field bandage (+30 HP) |
| 6 | Craft reinforced bandage (2 fiber T2, 1 fiber T1) |
| 7 | Use reinforced bandage (+60 HP) |
| Esc / left click | Release / recapture mouse |
| R | Restart scene |

Each harvesting profession starts at level 1. Harvesting grants profession XP.
Level 2 requires 60 XP in that profession; **T2** resources also require the
crafted scavenger tool. All gathering and crafting rules live in the game
layer; Cgame physics nodes supply collision and interaction.

The HUD shows food, water, low-tier resources, advanced resources, profession
levels, tool status, bandages, crafting XP and recent gameplay messages.

## Verification

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test.gd
```

The automated test covers the loaded scene, supplies, hunger/thirst, Tier 2
access restrictions, profession levelling, tool crafting, healing, and physical
frames. It must return exit code 0 before merging. This file documents the
test; it does not claim that an executable has been run in this environment.

## One project, two gameplay pillars

- **Survival**: scavenging, zombies, hostile weather, thirst, hunger, combat,
  shelters, vehicles, and cooperative exploration.
- **Sandbox RPG**: classless mastery, professions, gathering tiers, weapons,
  refining, crafting, player-to-player trading, towns, guilds, and contested
  locations.
- **Cgame engine**: reusable physics, rendering, navigation, multiplayer
  primitives, streaming, profiling and editor tools.
- **Game project**: progression rules, balance, recipes, enemy logic,
  inventories, combat abilities, buildings and item economy.

Create new Cgame APIs only after a missing reusable capability is documented,
tested natively, and exercised here. Keep `demo/days_after` as the canonical
integration scene; other experiments may remain as isolated labs until their
features are intentionally migrated.

## Next milestones

1. Consolidate existing zombie/combat experiments into this project.
2. Save/load and data-driven item definitions, tiers and equipment slots.
3. Crafting workbenches, base building, loot and repair durability.
4. Server-authoritative inventory, trading and multiplayer combat.
5. Zone streaming, faction/reputation systems and PvP rules, with performance
   and synchronization tests.

This is a prototype, not an already completed MMO.
