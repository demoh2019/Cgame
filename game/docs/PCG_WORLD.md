# PCG world generation

The engine's `pcg_graph` module (see `modules/pcg_graph/README.md`) drives three cosmetic layers on the client and two
gameplay layers on the server. Everything is feature-guarded: without the classes (`ClassDB.class_exists("PCGGraph")`) the
game runs exactly as before.

| Layer | Graph builder (`scripts/shared/pcg_graphs.gd`) | Consumer | Authority |
| --- | --- | --- | --- |
| Roadside dressing (barrels, crates, baskets, benches, stools along roads) | `roadside_dressing()` | `client/pcg_world_dressing.gd` | cosmetic |
| Biome ground clutter (rocks, stones; density per biome) | `biome_clutter()` | `client/pcg_world_dressing.gd` | cosmetic |
| Ruin debris (rubble, columns, stones around ruined cities) | `ruin_debris()` | `client/pcg_world_dressing.gd` | cosmetic |
| Loot caches (crates of loot tier 1..4) | `loot_caches()` | `server/pcg_spawns.gd` | server |
| Encounter spots (infected groups) | `encounter_spots()` | `server/pcg_spawns.gd` | server |

## Pipelines

* Roadside: spline sampler on `user_data["roads"]` -> transform (jitter, scale, snap) -> exclusion (hub plaza, settlements) -> surface filter -> noise density -> density filter -> asset rules.
* Clutter: surface sampler -> exclusion -> density noise -> biome mask (per-biome density) -> density filter -> surface filter -> self-prune -> transform -> asset rules (per biome) -> cluster.
* Debris: surface sampler + point source (`user_data["ruins"]`, ruined-city centres) -> spatial query (keep inside radius) -> surface filter -> self-prune -> transform -> asset rules.
* Loot: point source (`user_data["pois"]`: candidate spots around depots, mines, ruined cities, bunkers, landmarks and ruin chunks; `density = tier / 4`) -> asset rules (the asset is the loot tier; a spot never rolls above its own tier) -> count limit.
* Encounters: surface sampler -> exclusion (hub safe zone + 25 m, settlements, plus a 40 m margin) -> surface filter -> self-prune (38 m) -> count limit.

## Client dressing (`PcgWorldDressing`)

Added in `online_main.gd` next to the far field (`setup(client.world)`, `update(position, delta)`). One `PCGComponent3D` per
graph: streaming on, cell 64 m, 1 cell per frame, MultiMesh per asset and 32 m cluster, `visibility_range_end` by tier.
Samplers are `world.height_at`, `world.biome_at`, `world.is_water`. Cells are generated synchronously on the main thread
(`ASYNC_CELLS = false`) because `WorldGen.height_at` keeps unsynchronised region caches; flip the constant when a
thread-safe sampler exists. Asset index -> mesh maps reuse `ModelCatalog` (scanned rocks and stones, `PROPS`, `RUINS`);
missing models fall back to plain shapes.

Budgets by `GraphicsQuality.level()` (re-read every 2 s):

| Level | Streaming radius | Visibility end | Clutter / roadside / debris spacing |
| --- | --- | --- | --- |
| 0 Performance | off | - | - |
| 1 Balanced | 1 cell | 75 m | 8 / 30 / off |
| 2 High | 2 cells | 120 m | 6 / 22 / 7 m |
| 3 Ultra | 3 cells | 170 m | 4.5 / 16 / 5.5 m |

Edit `PcgWorldDressing.TIERS` to change them.

## Server (`PcgSpawns`)

`PcgSpawns.attach(world)` is called from `GameServer._init` (and, for presentation only, from `GameClient.on_welcome`).
It sets `WorldGen.spawn_extender`; `WorldGen._generate_chunk` calls `extend(cell, data)` at the end and the extender appends:

* crates `{kind: "crate", pcg: true, tier, ...}` with ids `entity_id(cell, 700..711)`, at most 3 per chunk, never inside the hub
  safe zone, settlements, water or a building footprint;
* infected spawns `{pcg: true, ruin: false, ...}` with ids `entity_id(cell, 720..743)`, at most 8 per chunk
  (groups of 1-3 around a spot; spots per chunk by zone: 1, 1, 2, 2).

Both come from PCG graphs seeded by the world seed (`world_seed * 31 + salt`), independent of the chunk grid, so the same seed
always yields the same crates and spawns. Spawn lifecycle, loot and opening stay in `game_server.gd`: PCG entries use the
existing crate/spawn structures. `PcgSpawns.ENABLED := false` switches the whole thing off.

## Tweaking

* Graph parameters (exposed per builder: `ROADSIDE_PARAMETERS`, `CLUTTER_PARAMETERS`, `DEBRIS_PARAMETERS`, `LOOT_PARAMETERS`,
  `ENCOUNTER_PARAMETERS`) are overridden through the context/component `overrides` dictionary, e.g.
  `component.set_override("spacing", 7.0)` or `run_graph(..., {"max_per_chunk": 2}, ...)`.
* Biome density: `PcgGraphs.CLUTTER_BIOME_DENSITY`. Loot tiers and weights: the rule table in `loot_caches()`.
* Node properties not exposed as parameters are edited in the builders; `graph.validate()` must stay empty (tests check it).
* Caps: `PcgSpawns.MAX_CACHES_PER_CHUNK`, `MAX_ENCOUNTER_SPAWNS_PER_CHUNK`, `ENCOUNTERS_PER_ZONE`.

## Not covered

Ruin chunks produced by `WorldGen` (not city sites) get no debris. Clients without the module do not list PCG crates (the server
still does) and therefore cannot open them. Visual output was not verified in a running client.

Tests: `tests/test_pcg_world.gd` (graphs validate, determinism per seed, cell seams, caps, safe zones, missing-class path).
