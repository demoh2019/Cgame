# pcg_graph world nodes

World-building nodes in `pcg_world_nodes.h/.cpp` (category `World`, registered by
`register_pcg_world_nodes()`). They follow the core determinism rules: the node seed
comes from the world seed, node id and seed offset; per-point draws mix the node seed with
the input point seed **and its world position**, so results never depend on input order or
streaming cell. Inputs are never mutated. Every node that reads context samplers returns
`uses_environment() == true`.

Typical chain: `PCGPointSource(settlements) -> PCGRoadNetwork -> PCGSettlement ->
PCGBuilding -> PCGRuin -> PCGEnvironmentDressing`; terrain features
`PCGRiverNetwork`, `PCGStructure -> PCGLootPlacement`, `PCGEncounterPlacement`.

| Node | Inputs | Output | Unreal PCG | Houdini | Unity |
| --- | --- | --- | --- | --- | --- |
| `PCGRoadNetworkNode` | 0: settlement points (or `user_data[source_key]`) | `PCGSplineData` (width = `road_width`) | Spline Sampler + custom path-finding PCG node; PCG "Create Spline" graphs | Labs Road Generator / `Heightfield Path` (cost-surface routing) | Procedural road tools (Road Architect), A* over a terrain cost grid |
| `PCGRiverNetworkNode` | none (lattice sources from height sampler) | `PCGSplineData` chunks, width grows downstream | Landscape Splines + Water plugin rivers | Heightfield Erode flow / `Labs Flowmap`, `Heightfield Distance` + curve trace | River Auto Material / Gaia river spline stamps |
| `PCGSettlementNode` | 0: centers, 1: roads | Points: `footprint_x`, `footprint_z`, `kind` (0 house, 1 workshop, 2 well, 3 wall_post), `settlement` | PCG village graph: Surface Sampler + Spline Sampler + Self Pruning + Attribute Filter | Labs Building Generator lot layout / `Labs Lot Subdivision`, Copy to Points | Village generators (Procedural Worlds Gaia), `ProBuilder` lot prefabs |
| `PCGCityNode` | 0: centers | Points: `footprint_x`, `footprint_z`, `district` (0 core, 1 residential, 2 industrial), `block`; static `layout_blocks(seed, rect, block_size, street_width) -> Array[Rect2]` | PCG Grid / Subdivide + Proc Building (Procedural Content Generation Framework) | Labs `Block Subdivision`, `Labs City Generator`, Houdini Engine city HDAs | CityEngine-style rule sets, Gaia Urban, `Procedural City Generator` assets |
| `PCGBuildingNode` | 0: lot points | Points: `piece`, `floor`, `floors`, `building` (Piece enum: 0 floor, 1 wall, 2 corner, 3 door, 4 window, 5 roof, 6 rubble) | PCG Building graph with `Static Mesh Spawner` per module; Modular Building Kit + Data Layers | Labs Building Generator / `Modular Building` HDA, Copy to Points | Procedural Building Generation (rule-based prefab assembler), Prefab painter |
| `PCGRuinNode` | 0: building pieces | Same attributes; pieces decayed, `piece = 6` rubble points added | PCG Density Noise + Attribute Filter on building points | Labs `Wall Damage`, `Rubble` scatter, `Attribute Noise` + Delete | Destruction-by-mask scripts, `Ruins` kit with random enable |
| `PCGStructureNode` | 0: candidate sites | Points: `structure` (rule id), `footprint_radius` | PCG Static Mesh Spawner with weighted entries + Self Pruning (large radius) | Scatter + `Labs Prefab Placement`, Copy to Points w/ `pscale` | Gaia stamper / "Spawn Rules" with collision radius |
| `PCGLootPlacementNode` | 0: spots, 1: structures | Selected points + `loot_tier`, `loot_table` | PCG Attribute Filter + Weighted Select, Data Asset lookup | `Attribute Randomize`, `Switch` by band | ScriptableObject loot tables + spawn markers |
| `PCGEncounterPlacementNode` | 0: candidates, 1/2: points or splines to avoid | Points + `group_size`, `difficulty` | PCG Spatial Noise + Distance filter (Difference/Spatial Query) | `Attribute Wrangle` with `nearpoint` + `xyzdist` | AI Director spawn volumes with exclusion zones |
| `PCGEnvironmentDressingNode` | 0: sources, 1: splines (lamps) | Points + `asset`, `source` | PCG Spawn Actor / Static Mesh Spawner on Points from Spline Sampler | Scatter on points / curve (`Copy to Points`) | Prop scatter tools (Vegetation Studio / Polybrush) |

## Notes per node

* **Roads** — `route(seed, from, to, context, grid_step, slope_weight, water_penalty)` is a public
  static helper (A*, 8-neighbour grid, binary heap, deterministic tie-break). Edge cost =
  `distance * (1 + slope_weight * grade^2)` plus `water_penalty * distance` on water cells.
  Network = Prim MST (ties by index); `loop_detour_ratio > 1` adds up to `max_extra_edges`
  of the 64 shortest non-tree pairs whose graph detour exceeds the ratio. Endpoints are the exact
  input positions.
* **Rivers** — sources are lattice local maxima (spacing `source_spacing`, above
  `min_source_height`) ordered by height. Steepest descent with `momentum`; polyline `y` never
  rises; pits are filled by ray-searching the lowest rim within `max_fill_depth`; rivers end at
  water, outside bounds, at `max_length`, or merge into an earlier river inside `merge_radius`.
  Width = `base_width + width_growth * sqrt(drainage)`, emitted as chunks of constant quantised
  width. Rivers are traced per evaluation bounds; use bounds large enough to contain whole basins.
* **Settlements** — road-front lots first, then rings of lots facing the center, optional wall
  post ring (`wall_radius`). Lots are circles (footprint diagonal) tested against each other, roads,
  slope, water and bounds.
* **City** — grid layout cuts the rect into jittered columns/rows (`layout_blocks`); radial layout
  places lots on concentric rings. District thresholds are distances from the center.
* **Buildings** — lot yaw rotates the whole building; walls face outward; exactly one door on
  floor 0; windows replace walls by `window_chance`; roof pieces carry `floor = floors`.
* **Ruins** — removal probability = `base_decay + height_decay * floor/floors +
  noise_strength * (noise - 0.5) * 2` (floor tiles x0.3); rubble spawns at ground level near removed
  walls/roof pieces.
* **Structures** — rule table entries: `{id, radius, min_slope, max_slope, biomes, weight}`;
  sites processed in seeded priority order, overlaps rejected via a spatial hash.
* **Loot** — tier from the `tier_attribute` when present, else number of `tier_bands` thresholds
  passed by the distance from `origin`. Grouping is nearest structure (input 1), else a
  `group_cell` grid cell.
* **Encounters** — `difficulty` = bands passed by distance from `origin`;
  `group_size = group_size_min + draw + difficulty / 2`.
* **Dressing** — rules may match on an input attribute (`attribute`/`value`), e.g. `piece == 1`
  for walls or `piece == 6` for rubble; `lamp_spacing > 0` adds alternating-side lamps along input 1.

Tests: `modules/pcg_graph/tests/test_pcg_world_nodes.h`
(`bin/godot.* --headless --test --test-case="*PCGWorld*"`).
