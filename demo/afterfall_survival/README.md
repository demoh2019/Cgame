# Afterfall Frontier — Survival RPG vertical slice

An **original** top-down survival game prototype for our Cgame/Godot engine fork, combining genre-level ideas from a post-apocalyptic survival RPG and a sandbox MMORPG. No third-party art, dialogue, maps, brand assets or copyrighted source code are used.

## Play

Open this folder as a project in Godot 4.5+ (or the Cgame editor) and run the main scene.
For CLI smoke tests:

    godot --headless --path demo/afterfall_survival --script res://tests/smoke.gd

## Controls

- WASD / arrow keys: move
- E: gather the nearest resource marker
- TAB: cycle crafting recipes; C: craft the current recipe
- Left click / Space: attack nearby infected
- 1 / 2 / 3: equip club / crafted spear / crafted axe
- F: heal with a crafted bandage
- H: eat berries; J: drink water

## Current vertical slice

- Deterministically generated asset-free wasteland with six kinds of resource node.
- Hunger, thirst and HP; low supplies reduce movement speed, starvation causes damage.
- Gather, craft and equip two weapon types; the equipped weapon defines attack power and reach (a foundation for classless roles).
- Infected pursuit, melee attacks, scaling night-time spawn pressure, combat and gathering mastery.
- Build a safe campfire zone from wood/stone, gain proficiency through use, and follow a starter quest chain.
- Soft loss on death: lose half of unsecured base materials and return to refuge.
- Rendering and combat use standard Godot 4.x API: engine changes are intentionally **not** required for this slice.

## Follow-up architecture

The next game increments should add persistent inventory/storage and save migrations; recipes as versioned resources; more equipment-based abilities and an ability bar; NPC trading; server-authoritative inventory/crafting/combat; deterministic tick-based prediction and reconciliation; partitioned world streaming; AI perception/pathfinding; mounts and physics-driven vehicles; building ownership and destruction. High-risk PvP and full loot belong only in dedicated opt-in zones and after authoritative multiplayer is implemented.

Game systems must stay in the *game*. Only general reusable or performance-critical primitives (such as large-world streaming, physics queries or replication) should move into the *engine*. Porting third-party implementations requires license review and regression tests.

## Scope and limitations

This is a **single-player prototype**, not a finished MMO. There is no backend, player market, multiplayer, persistence, terrain collision, character animation or content pipeline yet. Do not present this game as production-ready until the CI smoke run and editor playtests pass.
