# Experimental systems: purpose, status, guarantees, limitations

Each section covers one library family added to `game/scripts/`. Guarantees and limitations are taken from the
header comments of the files (linked to their generated API pages) and from the documented behaviour; where a
header says nothing, this page says so rather than guess. All of these are **Experimental** in the sense of the
[versioning policy](versioning.md).

**Status key.** *Library* = code and headless tests only, not called by the running game.
*Wired* = called by the game client or server.

Features that are wired today: FFT sea detail (`client/sea_fft_detail.gd`), the HTN raid boss in `server/game_server.gd`,
Voronoi barricade debris (`client/barricade_debris.gd`), VFX-graph lightning sparks, `--trace` frame capture,
Utility AI infected targeting (`shared/infected_target_utility.gd`), lag compensation (`server/lag_compensation.gd`),
the trade journal (`server/trade_journal.gd`), motion warping (`client/motion_warp.gd`) and virtual audio voices
(`client/audio_virtual_voices.gd`). Everything else below is library-only unless its section says otherwise.

Contents: [1 Planners](#1-planners-goap-htn-utility-ai) - [2 Navigation](#2-navigation) - [3 Terrain](#3-terrain) -
[4 Water](#4-water-ocean-and-shallow-water) - [5 Fluids](#5-fluids) - [6 Netcode](#6-netcode-rollback-prediction-snapshots) -
[7 Transactions and sharding](#7-transactions-sharding-and-server-durability) - [8 Animation](#8-animation-ik-retargeting-motion-matching-mocap-faces) -
[9 Fracture and soft bodies](#9-fracture-and-soft-bodies) - [10 Acoustics](#10-acoustics) - [11 Audio graph](#11-audio-graph) -
[12 VFX graph](#12-vfx-graph) - [13 Cinematics](#13-cinematics) - [14 PCG](#14-pcg) - [15 World partition](#15-world-partition-bake) -
[16 Virtual geometry](#16-virtual-geometry) - [17 Occlusion](#17-occlusion) - [18 Virtual texturing](#18-virtual-texturing) -
[19 Probe GI](#19-probe-gi) - [20 Path tracer](#20-path-tracer) - [21 Virtual shadow pages](#21-virtual-shadow-pages) -
[22 Visual scripting](#22-visual-scripting) - [23 StateTree and smart objects](#23-statetree-and-smart-objects) -
[24 Mass entity and crowds](#24-mass-entity-and-crowds) - [25 Tools](#25-tools-and-diagnostics)

---

## 1. Planners (GOAP, HTN, Utility AI)

- **Purpose.** Three decision-making libraries. [`goap_planner`](api/shared/goap_planner.md): A* over world states with action
  costs, preconditions and effects (F.E.A.R. style). [`htn_planner`](api/shared/htn_planner.md): depth-first decomposition of compound tasks
  into primitives with backtracking. [`utility_ai`](api/shared/utility_ai.md): response curves and compensated multiplication of
  considerations (Infinite Axis Utility System), plus `best()` selection.
- **Status.** Utility AI is **wired** through `shared/infected_target_utility.gd` (infected choose prey). HTN is **wired** for the raid boss:
  `shared/infected_raid_domain.gd` is the domain used by `server/game_server.gd`. GOAP is **library**.
- **Guarantees.** GOAP and HTN are deterministic: ties resolve by insertion/declaration order. The HTN planner simulates effects on a copy
  of the world state, so planning does not mutate the caller's state. Utility `combine()` returns 0 when any consideration is 0 (veto);
  `best()` keeps the first top score and returns -1 when nothing scores above zero; curve inputs are clamped.
- **Known limitations.** GOAP's heuristic counts unsatisfied goal keys scaled by the cheapest action cost and is a lower bound only for
  unit-ish costs (header). HTN returns failure when the root cannot be decomposed within `max_steps` expansions. Domains are plain data
  (Dictionaries); there is no validation beyond what planning discovers.

## 2. Navigation

- **Purpose.** [`hierarchical_pathfinder`](api/shared/hierarchical_pathfinder.md) (HPA* on a walkability grid, cluster rebuild through `invalidate_cluster()`),
  [`navmesh_stitching`](api/shared/navmesh_stitching.md) (tiled navmesh portals, polygon A*, funnel string pulling),
  [`navmesh_carving`](api/shared/navmesh_carving.md) (budgeted tile cache: obstacles subtracted from tiles, destroyed obstacles reopen routes and report changed tiles),
  [`off_mesh_links`](api/shared/off_mesh_links.md) (drop / jump / gap links from a heightfield), and
  [`destruction_replication`](api/shared/destruction_replication.md) (compact server-to-client state for destructible objects, used with carving).
- **Status.** Library. (Existing game navigation in `shared/travel_navigation.gd`, `shared/road_network.gd` is separate.)
- **Guarantees.** Hierarchical grid paths use 4-connected unit-cost steps and are valid. Off-mesh link generation is deterministic (row-major scan,
  each pair once). Carving re-carves only the touched tiles and re-links neighbours under a per-update budget. Destruction deltas carry
  absolute values, so a lost or duplicated packet costs bandwidth, never correctness (header).
- **Known limitations.** HPA* paths are valid but not guaranteed to be globally shortest. The navmesh code is 2D (XZ plane polygons). The
  Recast/Detour ideas are re-implemented in GDScript, so there is no voxelisation step: tiles must be supplied as convex polygons.
  Funnel orientation convention ("left" = positive cross product relative to travel direction) must be respected by callers.

## 3. Terrain

- **Purpose.** [`hydraulic_erosion`](api/shared/hydraulic_erosion.md) (droplet erosion + thermal talus pass),
  [`terrain_splines`](api/shared/terrain_splines.md) (roads, rivers, bridges, deformation along splines),
  [`terrain_edit_layers`](api/shared/terrain_edit_layers.md) (chunked non-destructive layers with brush strokes, splat painting, undo),
  plus the older generators [`world_gen`](api/shared/world_gen.md), [`world_rivers`](api/shared/world_rivers.md), [`world_roads`](api/shared/world_roads.md).
- **Status.** Library (the game's world generation uses its own pipeline).
- **Guarantees.** Erosion is deterministic per seed, conserves sediment (picked up material is deposited at the latest where the droplet dies),
  takes and returns plain height arrays (index `y * width + x`). Edit layers never modify the base heightfield; neighbouring chunks share a seam row/column.
- **Known limitations.** Spline "raise" only lifts terrain up to the spline height (embankment) and never lowers it. In edit layers, property changes
  (visibility, opacity, blend, order) are not on the undo stack; only brush strokes and fills are (header).

## 4. Water (ocean and shallow water)

- **Purpose.** [`fft_ocean`](api/shared/fft_ocean.md): Tessendorf Phillips-spectrum heightfield via inverse 2D FFT, sampleable on the CPU for buoyancy.
  [`shallow_water`](api/shared/shallow_water.md): virtual-pipes solver for floods and puddles.
- **Status.** FFT ocean is **wired** as the FFT detail layer on the sea: `client/sea_fft_detail.gd` evaluates the spectrum 10 times a second into two small height
  textures that the water shader cross-fades; High/Ultra presets only, lower presets keep the pure Gerstner surface. Shallow water is **library**.
- **Guarantees.** Spectrum is built deterministically from a seed; the height grid is real and tileable. Shallow water keeps depth >= 0 and has closed boundaries, so volume is conserved.
- **Known limitations.** FFT grid size `n` must be a power of two. The sea detail layer is cosmetic chop on top of the Gerstner swell, gated by quality preset.
  Shallow water is a heightfield (no overhangs, no splashes), 4-neighbour pipes.

## 5. Fluids

- **Purpose.** [`sph_fluid`](api/shared/sph_fluid.md): 3D position-based fluids (density constraint, artificial pressure, XSPH viscosity, optional vorticity confinement),
  fixed box domain, sphere obstacles with two-way momentum transfer. [`flip_fluid`](api/shared/flip_fluid.md): 2D FLIP/PIC on a MAC grid with solid cells, destructible walls
  (`set_solid`) and a moving circle obstacle.
- **Status.** Library.
- **Guarantees.** Neighbour search uses a uniform counting-sort grid. Both are written from the published algorithms (see headers for credits).
- **Known limitations.** SPH domain is a fixed box; obstacles are spheres only. FLIP is 2D with a circle obstacle. Both run in GDScript on the CPU; the repo contains no
  measured particle-count budget for the game, so choose counts by profiling (see [tools](#25-tools-and-diagnostics)).

## 6. Netcode (rollback, prediction, snapshots)

- **Purpose.** [`rollback_netcode`](api/shared/rollback_netcode.md): GGPO-style input buffers, prediction, rollback and resimulation, bounded snapshot ring, per-frame checksums with desync detection,
  input delay and a prediction window that stalls when exceeded. [`client_prediction`](api/shared/client_prediction.md): server-authoritative movement prediction with reconciliation and decaying visual error offset.
  [`snapshot_delta`](api/shared/snapshot_delta.md) / [`snapshot_baselines`](api/shared/snapshot_baselines.md): delta compression against the last acknowledged baseline.
  [`lag_compensation`](api/server/lag_compensation.md): server rewind of survivor positions for PvP hits.
- **Status.** Lag compensation is **wired** (`game_server.gd` holds a `lag_history`). Client prediction and snapshot deltas are part of the game's networking.
  Rollback netcode is **library**.
- **Guarantees.** Rollback requires `step` to be a pure deterministic `Callable(state, inputs, dt) -> Dictionary`; it receives a deep copy. A frame is confirmed once real inputs of every player
  are known for it and all earlier frames. Lag compensation rewind is capped so high-ping players cannot hit around corners. Reconciliation snaps instantly above `error_threshold`.
- **Known limitations.** Rollback is transport-agnostic: the caller must move `drain_outgoing()` entries and feed `add_remote_input()`. Non-deterministic step functions
  desync; the checksum report only detects that. `client_prediction`'s `apply` must match the server's movement code exactly.

## 7. Transactions, sharding and server durability

- **Purpose.** [`transaction_coordinator`](api/server/transaction_coordinator.md): two-phase commit with durable decision log and a persistent order book.
  [`world_sharding`](api/server/world_sharding.md): region-to-zone-server assignment, rebalancing with hysteresis, ghost replication near borders, idempotent two-step player handoff.
  [`trade_journal`](api/server/trade_journal.md): durable redo log for two-account deals. [`save_migrations`](api/server/save_migrations.md): versioned save migrations.
  [`replay_recorder`](api/server/replay_recorder.md): deterministic input-log recorder and replayer.
- **Status.** Trade journal is **wired** (fsynced post-deal snapshots written before the atomic backend pair commit, replayed on restart with the same transaction id).
  The others are **library**.
- **Guarantees.** 2PC: the COMMIT decision is logged durably before delivery; `recover()` re-delivers a logged decision, and no decision means presumed abort; participants must treat commit/abort as idempotent.
  Sharding moves a region only when that strictly lowers peak load, outside a hysteresis band. Migrations are single-step (+1), pure, never mutate the caller's data, and refuse gaps and downgrades.
  Replays: only `cmd_*` methods and `submit_input` can be replayed, so a recording cannot call privileged entry points; per-tick 64-bit FNV-1a state hashes locate the first divergence.
- **Known limitations.** The coordinator and sharding planner are in-process libraries; there is no network transport or multi-process deployment in the repository. Superseded sides of a trade are never written back by design.
  Replays are valid only for the build that produced them.

## 8. Animation (IK, retargeting, motion matching, mocap, faces)

- **Purpose.** [`rig_ik`](api/client/rig_ik.md) (two-bone IK with pole, FABRIK with cone/hinge constraints, full-body IK, aim, Skeleton3D helpers),
  [`rig_retarget`](api/client/rig_retarget.md) (bone-name maps, rotation transfer, hips scaling, foot IK),
  [`motion_matching`](api/client/motion_matching.md) + [`motion_db_builder`](api/client/motion_db_builder.md) (24-dimension pose-search database, k-means bucket index, synthetic foot cycles, pruning),
  [`mocap_cleanup`](api/client/mocap_cleanup.md) (One Euro and Butterworth filtering, spike removal, gap filling, foot-skate cleanup, root-motion extraction, key reduction),
  [`lip_sync`](api/client/lip_sync.md) and [`facial_animation`](api/client/facial_animation.md) (rule-based visemes, layered blend-shape graph),
  and [`motion_warp`](api/client/motion_warp.md).
- **Status.** Motion warping is **wired**. The rest is **library**.
- **Guarantees.** IK and cleanup are pure math on arrays, so they run headless. Motion matching search through the bucket index is exact (triangle-inequality pruning).
  Lip sync and blinks/saccades are deterministic.
- **Known limitations.** Lip-sync grapheme-to-phoneme covers English and Cyrillic transliteration only (header). Retargeting targets humanoid skeletons;
  rig dictionaries need parents listed before children. The motion database must be built from supplied data (or the synthetic builder cycles); no mocap assets ship with it.

## 9. Fracture and soft bodies

- **Purpose.** [`voronoi_fracture`](api/shared/voronoi_fracture.md): fracture a box into convex Voronoi cells. [`xpbd_cloth`](api/shared/xpbd_cloth.md) and [`xpbd_rope`](api/shared/xpbd_rope.md):
  XPBD cloth (stretch, shear, bending, collision, self-collision, tearing) and rope (distance/bending, self-collision, knot heuristic). [`hair_strands`](api/client/hair_strands.md): guide-strand hair.
- **Status.** Voronoi fracture is **wired** for barricade debris (`client/barricade_debris.gd`; deterministic fracture seeds replicate through `destruction_replication`). `client/cloth_flag.gd` is a separate in-game cloth visual.
  The XPBD cloth/rope and hair libraries are **library**.
- **Guarantees.** Fracture cells are the intersection of the box half-spaces with one bisector per other site. Cloth grid layout is fixed (row 0 is the top edge, local -Y is down, +Z is the front normal).
- **Known limitations.** Fracture input is a box. Cloth and rope self-collision use a spatial hash; the rope knot test is a crossing-number heuristic, not a topological proof. Hair ribbons are expanded in the vertex shader `assets/shaders/hair_strand.gdshader`.

## 10. Acoustics

- **Purpose.** [`acoustic_rooms`](api/client/acoustic_rooms.md): RT60 (Sabine / Eyring) from box geometry and synthetic impulse responses.
  [`audio_portals`](api/client/audio_portals.md): Dijkstra over portals, virtual source position, closed-portal attenuation, diffraction low-pass.
  [`audio_virtual_voices`](api/client/audio_virtual_voices.md): virtualisation of long sounds refused for lack of voices.
- **Status.** Virtual voices are **wired**. Rooms and portals are **library**.
- **Guarantees.** A virtualised sound keeps advancing silently and is promoted at the right offset (the result's `offset`) when a voice frees up while it still runs.
- **Known limitations.** Absorption coefficients are rounded, approximate handbook values (header). Rooms are boxes. The diffraction model is "UTD-inspired", not a wave solver.

## 11. Audio graph

- **Purpose.** [`audio_graph`](api/client/audio_graph.md): MetaSounds-style node graph rendered block-wise into sample buffers or `AudioStreamWAV` (oscillators with polyBLEP, noise, ADSR/AR, RBJ filters, smoothing, delay and more).
  Companions: [`procedural_sounds`](api/client/procedural_sounds.md), [`audio_mix_snapshots`](api/client/audio_mix_snapshots.md).
- **Status.** Library.
- **Guarantees.** Assets are plain Dictionaries (`nodes`, `connections`, `output`). A connection to `X` replaces the constant param; to `X_mod` it is added; several connections to one input are summed.
  A delay output never depends on the current block, so a delay may close a feedback loop.
- **Known limitations.** Rendering is CPU, block-based, in GDScript. Envelopes are linear segments. See the node table in the file header for the exact vocabulary; unknown node types are not supported.

## 12. VFX graph

- **Purpose.** [`vfx_graph`](api/client/vfx_graph.md): Niagara-style CPU particle runtime (structure-of-arrays, spawn/update modules, death/collision event routing between emitters).
  [`vfx_graph_node`](api/client/vfx_graph_node.md) renders each emitter as one `MultiMeshInstance3D`. [`vfx_presets`](api/client/vfx_presets.md) holds ready emitters.
- **Status.** **Wired** for lightning sparks (storm lightning). Other presets are library.
- **Guarantees.** Module vocabulary is fixed (see the header: spawn_rate, spawn_burst, initial_*, gravity, drag, curl_noise, vortex, attractor, *_over_life, collide_plane, kill_below_plane).
  The two plane modules run after integration.
- **Known limitations.** CPU simulation only; particles are simulated in the node's local space. `max_particles` bounds each emitter. Curl noise uses Godot's `FastNoiseLite`.

## 13. Cinematics

- **Purpose.** [`cinematic_sequence`](api/client/cinematic_sequence.md): Sequencer-style multi-shot timeline (transform, float, event, animation tracks; Catmull-Rom positions, squad rotations; serialization).
  [`cinematic_player`](api/client/cinematic_player.md): plays it onto bound nodes. Float tracks `fov`, `focus_distance`, `aperture`, `exposure` drive the current camera.
  Supporting looks: `cinematic_bloom`, `cinematic_color_grade`, `cinematic_fog`. An editor addon lives in `addons/cgame_sequencer`.
- **Status.** Library (addon is editor tooling).
- **Guarantees.** Sampling and serialization are data-only and headless-testable. `binding:property` tracks drive any property of a bound node.
- **Known limitations.** Depth-of-field and exposure tracks only take effect when `CameraAttributesPractical` is present on the camera (header).

## 14. PCG

- **Purpose.** [`pcg_graph`](api/shared/pcg_graph.md): UE5-PCG-style typed point-data graph runtime (samplers, density filters, pruning, difference, spawners, subgraphs, extension API, incremental cache, per-node debugger, per-partition-cell execution).
  [`pcg_presets`](api/shared/pcg_presets.md) and [`pcg_graphs`](api/shared/pcg_graphs.md): `forest_scatter`, `ruins_debris`, `cave_rocks` and game graphs. [`pcg_spawns`](api/server/pcg_spawns.md): server-side use.
  Related generators: [`procedural_caves`](api/shared/procedural_caves.md), [`procedural_buildings`](api/shared/procedural_buildings.md).
- **Status.** Partially wired: `shared/pcg_graphs.gd` is loaded by `client/pcg_world_dressing.gd` (world dressing) and `server/pcg_spawns.gd` (loot caches / encounter spots). The preset graphs in `pcg_presets.gd` are library.
- **Guarantees.** Deterministic per `graph_seed` (SplitMix64 mixer). Node outputs are cached and shared, and nodes must never mutate their inputs. `partition_execute()` crops outputs to the exact cell, so the union of all cells equals an unpartitioned run (tested).
  `validate()` returns the list of pin/type errors.
- **Known limitations.** Data types are the seven listed in the header (points, spline, volume, landscape, mesh_instances, scene_instances, layer_weights); array pins are written `type[]`. Neighbour-dependent nodes need a `margin` in partitioned execution to see context.

## 15. World partition bake

- **Purpose.** [`world_partition_bake`](api/shared/world_partition_bake.md): hierarchical grid cells, always-loaded actors, data layers, HLOD clusters, one-file-per-actor storage, incremental diffs, predictive streaming (`cells_to_load`).
  Related: [`data_layers`](api/shared/data_layers.md), `addons/cgame_world_partition` (editor).
- **Status.** Library (the game streams chunks with its own systems, e.g. `client/chunk_view.gd`).
- **Guarantees.** `stable_guid()` is deterministic (same seed, same GUID). Cells are keyed `group|level|x|z`; an actor larger than a cell goes to a coarser level (up to `MAX_LEVEL` 8). `cells_to_load` sorts nearest-first with ties by key and skips cells of disabled data layers.
  One-file-per-actor writes use tmp file + rename.
- **Known limitations.** Streaming range per layer comes from the dictionary you pass; the default is twice the level's cell size. Navmesh stitching is in a separate library ([navigation](#2-navigation)).

## 16. Virtual geometry

- **Purpose.** [`meshlets`](api/shared/meshlets.md): cluster building with bounding spheres and normal cones, cone and frustum culling.
  [`cluster_lod`](api/shared/cluster_lod.md): cluster DAG with locked group borders and screen-space-error cut selection. [`occluder_simplifier`](api/shared/occluder_simplifier.md) feeds [occlusion](#17-occlusion).
- **Status.** Library, CPU only (nothing is rendered through it).
- **Guarantees.** Group-shared LOD spheres mean the selected cut has no cracks or overlap (header). Default meshlet limits are 64 vertices and 124 triangles.
- **Known limitations.** Vertices must be welded (shared by index). Triangle winding follows Godot (front faces clockwise). There is no GPU rasteriser or streaming; the output is index lists for you to render.

## 17. Occlusion

- **Purpose.** [`occlusion_raster`](api/shared/occlusion_raster.md): low-resolution software depth rasteriser plus a max-depth Hi-Z pyramid; test AABBs one by one or in bulk (`test_many`).
- **Status.** Library (dungeon visibility uses the separate `client/dungeon_occlusion.gd`).
- **Guarantees.** Conservative: when unsure, visible. Depth is view distance (clip-space w), independent of reversed-Z and GL/D3D clip conventions. Empty texels hold INF.
- **Known limitations.** Perspective projections only. `temporal_reproject()` is approximate: disocclusions can leak stale occluders, so depth is pushed 5% farther and only finite single texels are splatted (header).

## 18. Virtual texturing

- **Purpose.** [`virtual_texture`](api/client/virtual_texture.md): page table, feedback-driven requests, LRU physical page cache, mip fallback, indirection image for shaders.
- **Status.** Library.
- **Guarantees.** The lowest (1-page) mip is pinned and always resident, so every virtual page can fall back to a resident ancestor. Page keys encode (mip, x, y) with `pack_page()`. Atlas slots include an edge-replicated border for bilinear filtering.
- **Known limitations.** Data and cache management only; no shader or GPU feedback pass is included in the file.

## 19. Probe GI

- **Purpose.** [`probe_volume`](api/shared/probe_volume.md): adaptive irradiance probe volume with L2 SH probes, temporal radiance-cache updates, LRU-budgeted cell streaming.
  [`sh_lighting`](api/shared/sh_lighting.md): 9-coefficient SH helpers.
- **Status.** Library.
- **Guarantees.** Geometry is abstracted behind a trace `Callable(origin, dir) -> {hit, color, distance, backface?}`, so it runs headless and against any scene. `evaluate_irradiance()` returns irradiance divided by pi (uniform radiance L gives exactly L).
  A budget of 0 means unlimited.
- **Known limitations.** Quality and cost depend on the trace callable you provide; the library does not ship a GPU tracer.

## 20. Path tracer

- **Purpose.** [`path_tracer`](api/shared/path_tracer.md) on top of [`bvh`](api/shared/bvh.md): CPU baking of per-vertex lighting and ambient occlusion, plus an offline photo/movie render mode. BVH uses binned SAH and Moller-Trumbore intersection.
- **Status.** Library, offline use.
- **Guarantees.** `sun_dir` is the direction light travels; output colours are linear; sky is constant radiance.
- **Known limitations.** CPU/GDScript, so intended for baking and offline renders, not per-frame use. No measured throughput is recorded in the repo.

## 21. Virtual shadow pages

- **Purpose.** [`virtual_shadow_pages`](api/shared/virtual_shadow_pages.md): clipmap levels, fixed-size pages, page requests from visible receivers, caster invalidation, LRU physical page pool with cross-frame reuse.
- **Status.** Library (CPU bookkeeping only; it does not render shadow maps).
- **Frame flow.** `setup()` once, then per frame `begin_frame(light_dir, camera_pos)`, `request_for_receivers(points, pixel_footprints)`, `invalidate_casters(aabbs_moved)`, `end_frame()` (returns a Dictionary), then `is_resident()` / `page_table()`.
- **Guarantees / limitations.** The file header documents the design only (clipmap levels, LRU pool, cross-frame reuse); no further guarantees are stated, so none are claimed here. Rendering the pages is the caller's job.

## 22. Visual scripting

- **Purpose.** [`visual_script_graph`](api/shared/visual_script_graph.md): Blueprint-style event graph with exec and data pins, state machines, delays, instruction budget per `fire()`.
  [`visual_script_library`](api/shared/visual_script_library.md): safe default function whitelist.
- **Status.** Library.
- **Guarantees.** Scripts reach only host-registered callables (never arbitrary `Object.call`); every library function validates its Variant arguments so a bad graph yields a recorded error and a neutral return value instead of a script error.
  The instruction budget stops runaway graphs. `register` can check argument counts (`argc`, -1 skips).
- **Known limitations.** Only the node types listed in the file header exist. Pure nodes are pull-evaluated.

## 23. StateTree and smart objects

- **Purpose.** [`state_tree`](api/shared/state_tree.md): hierarchical StateTree (enter conditions, tasks, evaluators, prioritised transitions, linked subtrees) with callables registered by name (whitelist).
  [`smart_objects`](api/shared/smart_objects.md): slot registry, exclusive claims with timeouts, query and placement scoring, per-behaviour interaction graphs.
- **Status.** Library.
- **Guarantees.** Selection takes the first child (depth-first) whose enter conditions pass; a state with children but no selectable child is not selectable. Assets are plain data. Claims time out.
- **Known limitations.** A state without tasks never completes by itself. Positions are world `Vector3`; 2D areas map x to world x and y to world z.

## 24. Mass entity and crowds

- **Purpose.** [`mass_entity`](api/shared/mass_entity.md): archetypes, structure-of-arrays fragments, processors with dependency ordering and optional parallel chunk execution.
  [`crowd_avoidance`](api/shared/crowd_avoidance.md): ORCA reciprocal avoidance with a spatial hash. Related client animation tiering: `client/anim_lod.gd`.
- **Status.** Library (the game has its own crowd tiering in the client; see `tests/test_crowd_animation_tier_planner.gd`).
- **Guarantees.** Fragment types are limited to `PackedVector3Array`, `PackedFloat32Array`, `PackedInt32Array`; archetype keys are independent of fragment order; ids carry a generation (24-bit index), so stale ids fail `is_alive()`. Processor order is a stable topological sort by `depends_on`; a cycle logs an error and runs the rest anyway.
- **Known limitations.** ORCA is a port of RVO2 (Apache-2.0, credited in the header); the neighbour search is a uniform hash, O(n) average. Parallel processors must not touch shared state outside their chunk.

## 25. Tools and diagnostics

- **Purpose.** [`trace_capture`](api/shared/trace_capture.md): scopes, counters and frame markers exported as Chrome/Perfetto trace JSON, with frame-regression comparison.
  [`perf_regression`](api/tools/perf_regression.md): median-of-N comparison between runs and a soak-test leak detector (least-squares slope).
  [`production_readiness`](api/tools/production_readiness.md): test-log parser and Markdown go/no-go report. [`docs_generator`](api/tools/docs_generator.md): this portal's API generator.
  Also: `shared/hitch_correlator.gd`, `client/frame_hitch_analyzer.gd`, `shared/save_validation.gd`.
- **Status.** `--trace` frame capture is **wired** (entry point `client/online_main.gd`). The others are command-line / library tools.
- **Guarantees.** Trace scopes are stored as complete events when they end, so a ring buffer that overwrites old events never leaves an orphaned begin/end pair. Regression limits widen by a `noise_factor` (default 0.5) share of run spread.
- **Known limitations.** Numbers produced are only as good as the runs you feed in; the tools do not ship baselines. Trace output is opened in ui.perfetto.dev or chrome://tracing.
