# HLOD Proxy Streaming (Cgame / Godot 4)

Runnable self-contained demo project for the Cgame fork's native WorldPartition3D.
This is a **scene-level HLOD prototype** with an offline, deterministic
MultiMesh proxy baker. It does not yet merge arbitrary meshes and materials
like the advanced Unreal HLOD builder, nor implement Nanite. It demonstrates the runtime handoff between nearby
detailed cells and lightweight distant proxies with no additional engine renderer.

## Architecture

- Two *existing* WorldPartition3D nodes share one camera as an observer.
- Detailed forest scenes stream at load radius 1, unload radius 2.
- Proxy forest scenes stream at load radius 4, unload radius 5.
- Detailed scenes generate deterministic trees through MultiMesh. Distant
  scenes use prebaked proxy files **only when the current manifest validates
  their source fingerprint and saved-file checksum**; otherwise the runtime
  falls back to procedural proxy scenes.
- The offline baker imports the detailed forest scene, subsamples instance
  transforms, substitutes a low-poly canopy mesh, and serializes each cell
  as a PackedScene with no runtime generation script. A SHA-256 manifest tracks
  the source scene, generator scripts, baking stride, and saved asset bytes.
  Repeat builds skip unchanged cells. It does not merge different meshes
  into a single static draw call.
- The full detail layer uses 160 trees per cell; the proxy layer uses 20 and a
  simpler canopy mesh. This reduces scene and geometry complexity away from the camera.
- Both layers remain independently budgeted, to limit new instances per frame.
- **Streamed physics and navigation:** detailed cells instantiate one coarse `StaticBody3D`/`BoxShape3D` ground collider and one shared-geometry `NavigationRegion3D` with a pre-authored walkable polygon. Distant HLOD proxies remain visual-only, including generated prebaked scenes. The native streamer calls `streaming_activated` after state restoration and `streaming_deactivating` before deferred deletion to disable collision and navigation registrations safely. The new `get_cell_simulation_stats` API reports loaded physics and navigation node counts in HUD.
- Press **N** to query a local walking path on a loaded Quest Hub or Combat Arena region. It waits two physics frames for Godot's NavigationServer3D map synchronization before calling `map_get_path`. The path point count is displayed in the HUD.
- `WorldPartition3D.get_cell_instance(Vector2i)` is used on cell_loaded/cell_unloaded
  to coordinate near/far geometry without stale references.
- A separate `hlod_crossfade_controller.gd` blends between detail and proxy
  scenes across a camera-distance margin, with a 0.4-second fade-in after
  near-scene streaming finishes. The visual blend updates at 30 Hz and does
  not write transparency repeatedly for stationary cells.
- `WorldPartition3D.max_unloads_per_frame` limits mass scene deletion after
  teleports. Quality modes apply unload budgets of 8/16/32 cells per frame.
- Press F to toggle crossfading at runtime for side-by-side FPS profiling.
- Native `WorldPartition3D` state snapshots keep quest rewards and combat
  results across scene unloading and re-instantiation; the root scripts
  implement `capture_streaming_state` and `restore_streaming_state`.
- Press C to claim the one-time Quest Hub reward, and B to record arena wins
  once the corresponding cell has streamed in. A landmark's 3D label and
  the HUD reflect the current saved gameplay progress.
- Press K to save a checkpoint to `user://cgame_demo_checkpoint.dat` and J
  to restore cell state, pin choices, **Data Layer activation states**, and player-camera transform. The demo
  writes a Godot Variant file with `FileAccess.store_var` and reads via
  `get_var(false)` to avoid instantiating object data from a save.
- **Runtime Data Layers:** combat cells (4,2), (4,3), (5,2) belong to `combat_event` (initially disabled); the Champion Shrine at (5,3) belongs to an independent `champion_event` layer. Press **T** to manually activate/deactivate combat scenes. Press **G** to pin the arena independently: a disabled layer still wins over a pin. Their progress survives layer transitions.
- **Native C++ signal-driven quest progression:** the demo subscribes to `cell_state_changed` and `layer_state_changed`. Claim the Quest Hub reward with **C** to unlock combat, record three arena victories with **B** to unlock the Champion Shrine, then approach (5,3) and press **V** to claim the unique champion reward. The game publishes gameplay state through `set_cell_state` so these events fire immediately. Stage activation and the one-time prize are included in checkpoints.
- The pure rule evaluator in `scripts/world_event_rules.gd` is tested with stock Godot, separate from the native module, so quest progression stays deterministic and easily extendable.
- **Competing runtime leases:** after claiming the Quest Hub reward, the quest owns an independent lease of the combat arena until three victories are recorded. Press **M** to acquire/release a second manually owned arena lease. Releasing either one leaves the other active. The HUD shows total active lease tokens and arena owner count. **G** still controls a separate manual pin; inactive combat Data Layers override both types of claims. Quest leases are reconstructed from progress after loading a checkpoint, while manual leases are intentionally transient.
- New native `WorldPartition3D.pin_cell()` keeps gameplay-important areas loaded. The scene starts with the **Quest Hub** at cell (0, 0) pinned, regardless of the moving camera. Press **H** to release/re-pin it, or **G** to pin/release the **Combat Arena** at (4, 2). Both landmarks have an emissive marker in their detailed cell scene. The HUD shows the pin count and residency status.
- Optional additional observer attached 180 m in front of camera prefetches
  detailed cells when PR #919 is included.

## Run

Build the Cgame fork with `world_partition` enabled and open this directory
as a Godot project:

```sh
scons platform=linuxbsd target=editor tests=yes -j"$(nproc)"
./bin/godot.linuxbsd.editor.x86_64 --editor --path modules/world_partition/demo
```

## Bake distant proxy assets

Run the baker with **any stock Godot 4 editor executable** (no native Cgame
extension is required for content generation). The default covers the full
13x13 configured demo grid and keeps one of every eight instances:

```sh
godot --headless --path modules/world_partition/demo --import --quit
godot --headless --path modules/world_partition/demo --script res://tools/bake_hlod_proxies.gd -- --radius=6 --stride=8
# A second identical invocation should report: Baked 0, skipped 169.
godot --headless --path modules/world_partition/demo --script res://tools/bake_hlod_proxies.gd -- --radius=6 --stride=8
godot --headless --path modules/world_partition/demo --script res://tests/hlod_bake_test.gd
```

For a quick validation without generating all 169 cells, use `--radius=1`.
Output is written to `res://generated/forest_proxy_X_Z.tscn` and kept out of
Git by the local `.gitignore`, along with `res://generated/hlod_manifest.json`.
The manifest records the SHA-256 of each stored proxy and a revision fingerprint
of the detail scene, its generating script, the baker, its manifest helper and
the selected stride. A second identical bake skips all 169 cells rather than
recreating their assets. Changing source inputs invalidates the cache and
forces regeneration. A partial bake deliberately replaces the manifest with
only the covered cells; other proxy scenes remain on disk but are excluded
until the full bake is run again. At runtime the demo checks the manifest
and each proxy's checksum before registering it; invalid or absent files use
the old procedural scene instead. The HUD reports the number of verified
proxy scenes and the measured checksum-scan time (milliseconds) at startup.
Restart the game after rebaking content.

The project uses Compatibility renderer so it can be inspected on low-end GPUs;
near/far proxy handoff is implemented without renderer-specific effects.

WASD to fly, Space/Ctrl for up/down, Shift for speed, P to toggle forward prefetch,
L to toggle distant proxy scenes, F to toggle near/far crossfade,
H to keep/release the Quest Hub, G to keep/release the Combat Arena pin,
M to acquire/release the arena's manual lease, N to test a local navigation path,
T to toggle the three-cell Combat Event Data Layer, C claim the hub reward,
B complete an arena round, V claim the Champion Shrine prize, K save and J load a
checkpoint, R to retry failed resource loads when the telemetry/retry API from PR #916 is present.
Without that engine API, R displays a warning instead of silently doing nothing.
HUD displays FPS, detail/proxy cell counts, the active quality preset and auto mode.

The optional adaptive quality controller monitors a 3-second time-weighted FPS
window. Under 48 FPS it reduces streaming distance/instantiation budgets, and
at 58+ FPS it increases them after a 10-second cooldown. The modes are
Performance (proxy radius 2), Balanced (4) and Cinematic (5). Switch with
keys 1/2/3 (manual), or Q (automatic toggle). This is an intentionally simple
demo controller, not a measured production GPU or frametime feedback system.

Quality controller assertions (after importing the project):

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/world_partition/demo --script res://tests/quality_controller_test.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/world_partition/demo --script res://tests/hlod_blend_test.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/world_partition/demo --script res://tests/cell_state_contract_test.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/world_partition/demo --script res://tests/physics_navigation_lifecycle_test.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/world_partition/demo --script res://tests/world_event_rules_test.gd
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/world_partition/demo --script res://tools/bake_hlod_proxies.gd -- --radius=1 --stride=8
./bin/godot.linuxbsd.editor.x86_64 --headless --path modules/world_partition/demo --script res://tests/hlod_bake_test.gd
```

## Limitations / validation

- Native `get_cell_instance()` is required for proxy handoff and `pin_cell()` is required for the gameplay residency controls; this stacked branch includes both.
- The Data Layers implementation has one named layer per cell rather than Unreal's full multiple-layer actor graph, and is strictly a runtime loading toggle, not a visibility-only toggle. Disabled-layer cells are unloaded within the existing per-frame unload budget, not removed synchronously.
- Lease tokens are held by their creator, not automatically persisted in checkpoints. Clients must release them on teardown and reacquire required cells from saved gameplay state. Manual demo tokens are discarded on checkpoint load.
- World event callbacks are synchronous Godot signals, not a multi-threaded quest scheduler or a general gameplay ability system. They respond to explicit cell-state updates, not arbitrary live-property changes.
- Pinning only controls residency; the **separate native cell-state API** captures
  and restores opt-in gameplay dictionaries. It does not serialize arbitrary
  child nodes, navigation meshes, physics bodies or network state automatically.
  Game checkpoints are written by `main.gd`, not by the native streamer itself,
  and this illustrative demo does not implement crash-safe atomic save swaps,
  compression, schema migration or encrypted/protected saves. It still respects
  native streaming budgets: saving a checkpoint does not force all cells to load.
- This is not the user's actual game project. The example lives in the engine
  source repository so it can be copied into a real Godot game once its source is available.
- The manifest checks are designed for integrity and content invalidation,
  not for cryptographic authentication of untrusted third-party assets.
  Computing SHA-256 for prepared scenes adds startup I/O; measure it for
  much larger worlds and consider a signed asset registry or optimized build
  catalog when scaling beyond the example grid.
- The proxy baker supports this demo's MeshInstance3D/MultiMeshInstance3D
  scene shape. It preserves source mesh materials and transforms but does
  not yet combine disparate materials, bake textures, or generate atlas
  impostors. Art direction and in-game profiling remain necessary.
- Forest art now includes **coarse streamed ground physics** and a pre-authored
  flat navigation polygon on detailed cells, but not detailed tree collisions,
  dynamic physics-state save, navmesh obstacle baking, AI agents, terrain painting,
  atmospheric scattering, impostor atlases or object-level persistence.
- `GeometryInstance3D.transparency` is compatible with the demo's GL
  Compatibility renderer but forces partially translucent geometry through
  the transparent pipeline and may cause sorting issues. Use F for A/B tests.
  In production, use suitable dithered HLOD materials or Godot's native
  visibility ranges when appropriate, with real GPU profiling.
- If detail or proxy is missing (or the camera instantly teleports past the
  blend band), the visible loaded tier is restored immediately; the system
  never fades its only available layer to invisible.
- This is a scene-level runtime blend, not automatic HLOD proxy baking.
- The test cases cover native lookup semantics, but the demo itself needs a real
  Godot editor/runtime test and GPU profiling before production use.
