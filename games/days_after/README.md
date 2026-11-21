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

## Playable gameplay loop

- Scavenge food, water and scrap in a greybox ruined zone.
- Harvest finite nodes of wood, fiber and stone to gain gathering XP.
- Craft a **makeshift spear** (2 wood + 1 scrap), **padded coat** (3 fiber + 2 scrap), and **bandage** (2 fiber).
- Equip a spear for 24 damage versus 6 bare-handed; a coat reduces incoming damage by 25%.
- Fight a pursuing infected, bandage wounds, and manage hunger, thirst and stamina.
- Gain crafting and gathering XP and see levels and equipment in the HUD.
- Crafting first checks all ingredients. Failed crafting does not consume anything.

## Tests and engine architecture

Run the headless smoke test command above against a compiled **Cgame** build. It checks scene structure, inventory, finite node harvest, crafting atomicity, progression, gear, combat and survival. A checked-in smoke test **is not** a passed test until executed on the built engine.

Gameplay state stays in `survival_state.gd`. Game-specific nodes are in the game; physics, raycasting and collision use Cgame's existing native API. Only extend Cgame itself for general-purpose engine capabilities that are truly missing; test the native API separately, then integrate into the game.

## Next milestones (not implemented yet)

- Pathfinding AI, expanded weapons/abilities and NPC behavior.
- Persistent loot, progression, save/load, procedural zones and streaming.
- Dedicated server authority, multiplayer synchronization and anti-cheat.
- Safe and contested regions, loot rules, PvP, guilds and territories.
- Tiered professions, gear durability, player markets and settlements.
- More post-apocalyptic simulation: weather, infection, building, vehicles.


## Visual significance LOD (Unreal-inspired)

Days After adds 96 small **non-colliding decorative rubble fragments** around
the ruined area. `debris_lod.gd` updates at 5 Hz and displays up to 18 nearby
fragments within 26 meters, with a 2-meter retention bonus to reduce flicker.
The new native Cgame API `SignificanceBudgetPlanner.select_world_priority_stable()`
supports up to 16 viewers; this game supplies the local player. A deterministic
GDScript fallback works on stock Godot. This is presentation-only LOD: no AI,
combat, resource pickup, collision, or network authority is skipped. The
headless smoke test checks budgeted visibility, distance culling and restoration.
Actual performance gains require profiling.

## Native PCG exclusion zones and instanced grass

The ruined-world scene now has deterministic collision-free grass distributed
with one `MultiMeshInstance3D` instead of one draw object per blade. A shuffled
625-cell source grid is thinned to at most 160 instances with a 2.1-meter
minimum 3D spacing. `PCGSpatialFilter3D.filter_indices_excluding()` subtracts
spherical zones around spawn, loot, ruined structures, and the barricade
**before** spacing. The native filter returns original indices in stable order,
so the output remains reproducible. A GDScript fallback maintains equivalent
results on stock Godot or old Cgame builds.

This affects visual decoration only, not gathering, physics collisions, AI,
spawning, networking, or server state. The standalone headless smoke verifies
exclusion boundaries, spacing, instancing limits, deterministic regeneration,
and native/fallback parity. No FPS improvement is claimed without profiling.

## Combined PCG sphere and box exclusions

The grass generator now calls the general-purpose
`PCGSpatialFilter3D.filter_indices_excluding_volumes()` native engine
method. In addition to its existing spherical masks, it uses six
axis-aligned rectangular volumes to protect the narrow ruin walls,
barricade, scrap container and supply crate from decorative foliage.
These boxes also exclude source points the spheres alone would retain.
Instances are still generated deterministically in one `MultiMesh`
batch with a 160-instance cap and 2.1-metre minimum center spacing.

With stock Godot or an older Cgame build, the GDScript fallback checks
the same inclusive sphere and box boundaries in the same source order.
The game smoke checks native/fallback parity, box-only candidate
coverage, reserved zone safety and regeneration stability. Gameplay
colliders, resource interactions, AI and networking remain untouched.
Measure a compiled game to determine actual CPU/GPU benefit.

## Stable PCG biome-density masks

The native Cgame `PCGDensitySelector` now performs a separate procedural
**density stage** before foliage spacing/exclusion. `pcg_density_policy.gd`
uses native density remap and stable-ID seeded probability selection when
available, with exactly equivalent stock-Godot fallback. The western
undergrowth is denser (92% point probability), while exposed eastern rubble
is sparser (35%). This is purely decorative, and does not change any
resource, collision, combat, or multiplayer code. The existing 625-cell
grid remains stable, but each cell makes its decision independently
of regeneration order; no shared RNG is advanced.

The original sphere/box exclusions are still applied *after* density filtering
and before 2.1 m spatial pruning, so every spawned visible plant remains safe.
Invalid density profiles fail open for cosmetic geometry to avoid disappearing
scenery. Visual quality and draw-call savings have not been benchmarked.

Headless regression:
```bash
godot --headless --path games/days_after --script res://pcg_density_smoke_test.gd
godot --headless --path games/days_after --script res://smoke_test.gd
```
Native doctests: `[PCGDensitySelector]`. Both are run in the
`native-pcg-spatial-filter.yml` workflow.
