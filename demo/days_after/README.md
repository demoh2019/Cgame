# Days After × Albion-inspired sandbox — playable integration slice

An **original, single survival-sandbox game** running inside the Cgame (Godot 4.8 fork).
The post-apocalyptic setting, names, rules and primitive visuals are original prototypes;
no code, maps, logos or art from other games are copied.

The project lives at `demo/days_after`. It intentionally combines:

- Survival and infected PvE: health, hunger, thirst, food, water, scavenging, ruins,
  real colliders and hostile infected.
- Sandbox progression: tiered wood/stone/fiber gathering, independent XP per
  gathering profession, crafting, and **classless equipment-defined combat**.
- A single shared inventory feeds survival, equipment, crafting and gathering.
  Upgrading tools unlocks tier-2 deposits; stronger crafted weapons increase damage;
  crafted armor reduces incoming damage. No fixed character classes.

This is an **offline vertical slice**, not an MMO. Player trading, a real player-run
economy, guilds, PvP zones, server persistence and networking are not yet implemented.

## Run

Open `demo/days_after/project.godot` in a compiled Cgame editor, or run the scene:

```sh
./bin/godot.linuxbsd.editor.x86_64 --path demo/days_after --editor
```

The scene is generated from built-in nodes and materials; no external assets required.

## Controls

| Keys | Function |
| --- | --- |
| WASD / Shift / Space | Walk / sprint / jump |
| Mouse / Left click | Look / attack infected (left click also captures cursor) |
| E | Gather targeted resource or pick up supplies |
| 1 / 2 | Eat food / drink water |
| 3 / 4 / 5 | Craft field bandage / craft & equip scavenger tool / use field bandage |
| 6 / 7 | Craft reinforced bandage / use reinforced bandage |
| 8 / 9 / 0 | Craft & equip scrap spear / padded vest / reinforced spear |
| Esc / R | Release cursor / restart scene |

## First 10-minute gameplay path

1. Scavenge supplies and manage hunger, thirst, and health.
2. Harvest tier-1 wood, stone and fiber. Each harvest grants profession XP.
3. Craft a scavenger tool using `wood_t1 ×2 + stone_t1 ×1`.
4. Reach gathering level 2 in a profession, then harvest its tier-2 deposit.
5. Craft a scrap spear, padded vest or reinforced spear. Equipment changes combat
   damage or armor without locking the character into a class.
6. Fight two infected in the outer ruins; melee hits and kills award combat XP,
   killed infected can yield research samples. Craft bandages to recover.

### Crafting recipes

| Item | Cost | Effect |
| --- | --- | --- |
| Field bandage | fiber T1 ×2 | +30 health |
| Scavenger tool | wood T1 ×2, stone T1 ×1 | Unlocks tier-2 harvesting at profession level 2 |
| Scrap spear | wood T1 ×2, stone T1 ×2 | 24 melee damage, equipped automatically |
| Padded vest | fiber T1 ×2, wood T1 ×1 | -25% incoming damage |
| Reinforced bandage | fiber T2 ×2, fiber T1 ×1 | +60 health |
| Reinforced spear | wood T2 ×2, stone T2 ×1, fiber T2 ×1 | 45 melee damage |

Bare-hand melee damage is 9. The weapon, tool, and vest are separate equipment
slots; the game does not use permanent classes.

## Headless smoke regression

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test.gd
```

The test covers scene node creation, collision, one-time pickups and gathering,
consumption, profession tier gates, transactional crafting, equipment stats,
bandaging, infected damage/death and finite player position.

**Compilation / runtime status:** changes are intended for Cgame 4.8; the
headless test must be executed with a built Cgame binary before merge.

## Engine and game ownership

- **Cgame engine** owns reusable rendering, physics, navigation, streaming,
  networking primitives and editor tooling.
- **This game** owns scavenging yields, recipes, gear, survival timers, enemy
  behavior and world population.
- If the design needs a generic engine capability that is genuinely missing,
  implement it in the engine with a native regression test and a matching game
  integration. Do not move game balance into the engine.

## Next cross-system vertical slices

1. **Persistence:** versioned character + world state, safe restoration of depleted
   resources and equipment, then saved/reconnected game sessions.
2. **Online server:** authoritative inventory, crafting, melee hits and movement,
   transaction IDs, rollback / exploit prevention and multiplayer tests.
3. **Economy and territory:** gathering/crafting market, item durability and
   player-to-player trading, guild territories, protected / contested PvP zones.
4. **World and content:** streaming regions, infected navigation/obstacles, weather,
   buildings and siege gameplay with stress tests and perf budgets.

These are planned work, not implemented features. Keep this one project as the
canonical game instead of maintaining competing `days_after` and `survival_mmo`
copies.
