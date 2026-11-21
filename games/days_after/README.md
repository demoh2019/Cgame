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

## Seeded biome-density foliage (native PCG)

The vegetation layer uses `PCGSpatialFilter3D.filter_indices_density()`
to sample each stable grid-cell ID from a per-cell density field before
applying the existing spheres/boxes and 2.1-metre spatial thinning.
The worn north–south approach has density 0.13, the dry northern area
0.46, the less overgrown western area 0.74 and the outer vegetation 0.94.

Sampling is deterministic for the same seed and IDs, even when source
points are reordered, and does not mutate the global RNG used by
gameplay. The scene still instantiates at most 160 decoration-only
instances in one `MultiMesh`, with no collision, AI, resource or
networking changes. The GDScript fallback matches the 31-bit native
integer hash and is smoke-tested for output parity and regeneration.

The density and performance benefits should be measured in a custom
Cgame build before claiming an FPS increase.

## Curved trail with PCG distance falloff

`FoliageScatter` uses native `PCGPathFalloff3D.sample_factors()`
to evaluate a multi-segment path from the outskirts past the survivor
spawn and ruined buildings. The route has a 1.8 m fully cleared
center and a 6 m soft outer margin: the sampled smoothstep factors
multiply existing deterministic biome densities *before* seeded
selection, exclusion volumes and 2.1 m instance spacing.

This is a native engine feature immediately exercised in the game.
Grass remains purely decorative and renders in a single
`MultiMeshInstance3D`; collision, enemy AI, gathering and networking
are not changed. The stock-Godot GDScript fallback implements the
same point-to-polyline distance mask and the smoke suite checks
native/fallback parity, corridor clearance, density blending,
placement bounds and reproducibility.

The path is currently a bounded XZ polyline mask, **not** an editor
spline tool or a navigation mesh. Performance gains are not claimed
without building and profiling Cgame.

## Native weighted instanced foliage variants

Days After now applies the reusable native Cgame
`PCGWeightedVariantSelector.choose_variants()` policy **after**
all previously implemented biome density, curved trail, sphere/AABB exclusion
and spacing filters. It uses the original grid-cell stable IDs, not
position in the final MultiMesh array. The same plant therefore keeps
its green (60%), dry-green (30%) or dead-straw (10%) variant across
regeneration, independent of point ordering. The proportions are
weights/probabilities, not exact guaranteed counts per tile.

The selection adjusts each blade's instance color, width and height
inside **one MultiMeshInstance3D**. No additional mesh nodes, gameplay
colliders, networking objects or draw calls per species are created.
Older Godot builds use `pcg_weighted_variants.gd` to reproduce the
same unsigned 32-bit selection. Native and fallback implementations
produce identical index choices with the same IDs, weights and seed.

Regression:
```sh
godot --headless --path games/days_after --script res://pcg_weighted_variants_smoke_test.gd
godot --headless --path games/days_after --script res://smoke_test.gd
```

The focused `native-pcg-spatial-filter.yml` workflow additionally
executes C++ `[PCGWeightedVariantSelector]` doctests. This is a
functional rendering-variation feature, not evidence of FPS gains.

## Instanced trail stones with native PCG route sampling

`TrailMarkers` now visualizes the existing curved survivor trail with
small, path-aligned stones. Its route comes directly from
`FoliageScatter.get_trail_points()`, so the visible markers and
no-foliage path falloff cannot drift to separate authored routes.

The new native `PCGPolylineSampler3D` samples the 3D polyline at an
approximately 1.35 m fitted arc-length interval; both endpoints are
included. A small GDScript fallback follows the same arc-length
calculation on standard Godot. Markers inside ruin/barricade/prop
exclusion AABBs are omitted. Remaining geometry is drawn in **one
MultiMesh**, with no collisions and no effect on harvesting, enemy AI,
navmeshes, world saves or network state.

The smoke verifies that sample distances stay bounded, both route
endpoints are preserved, all visible markers avoid structure zones,
the instance count matches the filtered positions, native/fallback
sampling agrees within floating-point tolerance and regeneration is
deterministic. Performance needs compiled-build profiling before
making FPS claims.
