# Afterfall Frontier — Cgame survival sandbox prototype

This is an **original playable Godot 4 / Cgame vertical slice**, informed by
two complementary design philosophies without copying proprietary code,
artwork, lore, maps, quests or characters:

- **Post-apocalyptic survival:** infected enemies, scavenging, hunger/thirst,
  field resources, gear, crafting and building/upgrading a persistent shelter
  with a protected stash.
- **Sandbox MMORPG progression:** no fixed character class; equipment decides
  combat style, gathering/crafting/combat professions level independently,
  more dangerous territories contain more valuable resources, and there is a
  basic settlement trader as a precursor to a true player market.

The focus is one **coherent loop** rather than a long list of disconnected
systems:

1. Start in the safe Haven with food, water and a few resources.
2. Collect trees, stone, plants and food with **E**. Make a survival axe.
3. Gather enough materials to build a shelter near the blue home building
   (press **B**). It protects stored materials from high-risk death.
4. Cross east into Frontier to scavenge scrap and mine ore. Infected chase
   and attack; fight with **F** and heal with a crafted bandage.
5. Return to the yellow Haven trader to craft better gear and sell resources.
6. Venture farther east into the Deadlands for rare alloy. Death here drops
   everything **carried** in a recoverable backpack, but not stashed items.

This project is completely asset-free: all map zones, characters,
infected and loot resources are rendered using native Node2D draw calls,
and the HUD uses standard Godot UI controls. No imported scene resources,
network services or paid packages are needed.

## Run

Open `demo/afterfall_frontier/project.godot` in Cgame or a compatible
Godot 4 editor, then press **F6/F5** (depending on editor's shortcut)
to run `main.tscn`. For CLI:

```sh
godot --path demo/afterfall_frontier
```

The game starts at a safe settlement and uses a top-down camera.

## Controls

| Key | Function |
|---|---|
| W A S D / arrows | Move |
| Shift | Sprint (uses stamina) |
| E | Gather nearest resource / retrieve death backpack |
| F | Melee attack nearest infected |
| Tab | Cycle crafting recipes |
| C | Craft selected recipe, at workbench if needed |
| B | Build/upgrade shelter beside blue home building |
| K / L | Store / retrieve a resource at the shelter |
| T | Sell one resource to Haven trader |
| Y | Buy clean water from the trader |
| H / J / R | Eat rations / drink / apply bandage |
| F5 / F9 | Save / load survivor, skills, items and shelter |

Prototype crafting recipes: survival axe, pickaxe, reinforced spear,
bandage and scrap armor. Recipes are data-driven in `rules.gd` and
use integer-atomic ingredient checks. The pickaxe unlocks ore and
alloy; the weapon changes combat damage, not the character's class.

## Territory and risk design

| Zone | Position | Gameplay | Loss on death |
|---|---:|---|---|
| Haven | x < 520 | Starter resources, crafting station, market, shelter | None |
| Frontier | 520–1159 | Infected, scrap and ore, double resource yield | About half of carried stacks |
| Deadlands | x ≥ 1160 | Harder infected, rare alloy, triple resource yield | Everything carried |

**Important distinction:** the level-risk and loot rules are playable
offline; the `pvp` field is a *design flag*. There is **no network PvP,
other players, guild territory server or player-driven market yet**.
The yellow trader is an offline fixed-price vendor with 10% selling tax.
Do not present it as Albion-like multiplayer economy already working.

Death creates a recoverable dropped backpack at the death location, which
expires after 240 seconds of game time. A built shelter's stash stays safe.
Equipment is currently inventory-based; spear/axe/armor automatically
improve damage/mitigation while carried.

## Architecture

- `rules.gd`: pure data definitions, territory constraints, resource
  values, recipes, carry limits and save-item whitelist.
- `survivor.gd`: rendering-independent domain model — atomic crafting,
  gather XP, shelter, protected stash, local trader, consumption, combat,
  risk-specific death and versioned profile snapshots.
- `world.gd`: native Godot scene boot, camera, deterministic resource
  layout, infected AI, interaction, death loot bags, UI and procedural art.
- `smoke_test.gd`: headless assertions for item quantities, crafting,
  workbench gating, XP, building, stash, trade, death/loot policy, save
  round-trip and running the real world for multiple physics frames.
- `project.godot` and `main.tscn`: directly importable Cgame project.

The underlying framework uses ordinary Godot 2D nodes, input, files,
rendering and physics process APIs. **No Godot engine modification is
required for this vertical slice.** When a real engine-level capability
is missing, it should be implemented and tested in the native
Cgame fork, and then exercised in this game. The physics PBF/FEM work
in separate engine PRs is not automatically gameplay-ready and is not
a dependency of this prototype.

## Persistence and validation

Press F5 to save a version-1 JSON snapshot to
`user://afterfall_frontier_v1.json`, and F9 to load it. Save data
includes inventory, protected stash, professions, needs, coins,
shelter, deaths, kills, day time and player location. Unknown
inventory keys are ignored, stack sizes and carry weight capped,
zones and progression bounded. A new game starts fresh unless
the player explicitly loads.

**Scope limitation:** only the survivor profile and location are
persistent in this milestone. World resource depletion, zombie
positions, dropped backpacks and multiplayer world authority are not
persistent. These need a dedicated world-state layer.

## Quality gate

```sh
godot --headless --path demo/afterfall_frontier --editor --import --quit
godot --headless --path demo/afterfall_frontier \
  --script res://smoke_test.gd
```

The smoke runner instantiates the **real main scene**, advances physics
frames, invokes resource interaction, checks scene objects and verifies
actual zone transitions; it also exercises the pure game model.

`.github/workflows/afterfall-frontier-game.yml` runs Python structural
contracts and engine headless import/smoke with a checksum-pinned official
Godot editor. The PR stays draft until both are green.

## Next milestones

1. **Real combat integration** — projectile weapons, hitboxes,
   knockback, line of sight, equipment durability and AI state machines.
2. **Base building** — placeable modular structures, collision validation,
   persistence, workstations and resource processing.
3. **Network authority** — dedicated server, account-independent player
   identity, server-owned inventories/transactions, prediction and
   anti-cheat; only then actual group play/PvP.
4. **Economy** — escrowed buy/sell limit orders, resource sinks, hauling
   and server-owned settlement markets.
5. **Territory/guilds** — owned outposts, timed assaults, zones and
   protected beginner experience.
6. **Production** — content pipeline, procedural zones, LOD/streaming,
   navigation mesh/pathfinding, animation, audio, accessibility and
   performance under player/NPC load.

The theme and mechanics are original; the goal is to combine **survival
stakes** and **economic sandbox agency**, not duplicate another game's
assets or intellectual property.
