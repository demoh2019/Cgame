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
| Esc | Release pointer |
| Left mouse button | Capture pointer |
| 3 | Craft field bandage |
| 4 | Craft and auto-equip scavenger tool |
| 5 | Use field bandage |
| 6 | Craft reinforced bandage |
| 7 | Use reinforced bandage |
| 8 | Craft and equip a rusty spear |
| 9 | Craft and equip a scrap vest |
| F | Melee attack (forward hit arc) |
| R | Restart the scene |

The HUD shows health, hunger, thirst, tiered inventory, profession levels,
crafting experience and interaction hints. Food restores 35 hunger points;
water restores 45 thirst points. Depletion reduces health. Pickups cannot be
collected twice.

Harvest wood, stone and fiber at tier 1 to raise separate gathering skills.
Every 60 XP unlocks another tier. Craft the scavenger tool from 2 wood T1
and 1 stone T1: it equips automatically and allows gathering tier 2 deposits
once the relevant skill reaches level 2. Deposits restore after 45 seconds.
Craft field bandages from 2 fiber T1 (heal 30 HP), or reinforced bandages
from 2 fiber T2 + 1 fiber T1 (heal 60 HP). Healing cannot be wasted at full HP.

A spear made from 2 wood T1 + 2 stone T1 increases melee damage; a vest
made from 3 fiber T1 + 2 stone T1 reduces incoming damage by 25%.
There are four infected with proximity pursuit, contact attacks and
combat experience rewards. Weapon damage depends on worn equipment, not a
fixed character class. Additional wood and stone T2 nodes support future gear.
Current enemy pursuit uses direct movement and can get stuck at obstacles.

These are original classless survival/RPG mechanics, not copied assets,
economy data or gameplay code from existing games. No MMO networking, PvP,
save/load, durability or player economy is claimed yet.

## Smoke test

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test.gd
```

The test verifies scene instantiation, one-time scavenging, inventory consumption,
stat recovery, resource depletion and respawn, skill tiers, tool requirements,
advanced crafting, bandage healing, melee combat, armor and finite position
over 10 physics frames.
A separate GitHub Actions smoke job exercises the game with official Godot 4.7.2
for compatibility; use compiled Cgame for engine-specific integration testing.

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
2. Replace basic zombie pursuit with navigation/obstacle avoidance and combat animation.
3. Data-driven crafting, loot containers, durability and a persistent profession tree.
4. A larger streaming map with optimized collision and profiling.

This is a foundation for iteration, **not** a complete survival game.
