# Days After — playable survival prototype

An **asset-free 3D survival vertical slice** for the Cgame (Godot-derived) engine.
Open `demo/days_after/project.godot` in the Cgame editor or run
`godot --path demo/days_after`.

## Play

- **W/A/S/D** move; **Shift** sprint (drains stamina).
- **Space** or **left mouse** melee attack. Zombies pursue and damage the survivor.
- **E** collect the nearest colored supply orb (within 2.25 m).
- **1** eat food, **2** drink water; both must be scavenged to avoid starvation.
- **R** restart after death.

Six zombies, six resource nodes, simple collidable buildings, an HUD, a
four-minute day/night cycle, HP/hunger/thirst/stamina and resource inventory
are implemented without downloaded models, textures or plugins.

## Architecture

- `world.gd`: level geometry, day/night time, spawning, melee hits, HUD, loot.
- `player.gd`: survivor input, movement, combat, survival stats, inventory.
- `zombie.gd`: chase/attack AI and health.
- `pickup.gd`: collectable resources.
- `smoke_test.gd`: headless scene/gameplay regression test.

```sh
godot --headless --path demo/days_after --script res://smoke_test.gd
```

**Engine-first rule:** reuse stable engine features before writing new engine
code. Add missing capabilities to Cgame with dedicated API tests; only then
integrate them into this game. The first vertical slice requires no native
engine modification.

## Next gameplay milestones

Navigation around obstacles, tool/weapon equip, zombie attack animation,
shelters and crafting, save/load, spawn director, terrain streaming and
multiplayer should be added incrementally and covered by repeatable smoke tests.
