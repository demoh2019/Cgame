# entity_view.gd

> Draws the moving things: other players, zombies and loot bags, smoothed between snapshots.

`res://scripts/client/entity_view.gd`

## Overview

Draws the moving things: other players, zombies and loot bags, smoothed between snapshots.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const ModelCatalog = preload("res://scripts/client/model_catalog.gd")`
- `const Meshes = preload("res://scripts/client/meshes.gd")`
- `const CharacterModel = preload("res://scripts/client/character_model.gd")`
- `const TrailBikeVisual = preload("res://scripts/client/trail_bike_visual.gd")`
- `const RaftVisual = preload("res://scripts/client/raft_visual.gd")`
- `const HandFlareVisual = preload("res://scripts/client/hand_flare_visual.gd")`
- `const Assets = preload("res://scripts/client/assets.gd")`
- `const LootLabel = preload("res://scripts/shared/loot_label.gd")`
- `const Ragdoll = preload("res://scripts/client/ragdoll.gd")`
- `const CharacterAnim = preload("res://scripts/client/character_anim.gd")`
- `const SnapshotSmoothing = preload("res://scripts/client/network_snapshot_smoothing.gd")`
- `const NetworkJitterBuffer = preload("res://scripts/client/network_jitter_buffer.gd")`
- `const LootDropBounce = preload("res://scripts/client/loot_drop_bounce.gd")`
- `const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")`
- `const EngineFeatures = preload("res://scripts/client/engine_features.gd")`
- `const GameplayCues = preload("res://scripts/client/gameplay_cues.gd")`
- `const AnimLod = preload("res://scripts/client/anim_lod.gd")`
- `const CombatAnimationPriority = preload("res://scripts/client/combat_animation_priority.gd")`
- `const CampfireFx = preload("res://scripts/client/campfire_fx.gd")`
- `const LootBeam = preload("res://scripts/client/loot_beam.gd")`
- `const CorpseBurn = preload("res://scripts/client/corpse_burn.gd")`
- `const BlobShadow = preload("res://scripts/client/blob_shadow.gd")`
- `const FarmPlotVisual = preload("res://scripts/client/farm_plot_visual.gd")`
- `const MotionWarp = preload("res://scripts/client/motion_warp.gd")`
- `const Combat = preload("res://scripts/shared/combat.gd")`
- `const LEAP_SECONDS := 0.55`
- `const CORPSE_MAX_SECONDS := 900.0 # A looted-out or abandoned body still goes eventually.`
- `const LOOT_GLOW_SHADER := preload("res://shaders/loot_glow.gdshader")`
- `const ZOMBIE_LOOK := {`
- `const ALERT_TINT := Color(1.0, 0.45, 0.4)`
- `const INTERPOLATION_DELAY := 0.12 # Baseline for 10 server snapshots per second.`
- `const TELEPORT_DISTANCE := 8.0`
- `const PIECE_DIR := "res://assets/models/kenney_building/town/"` - House piece models (Kenney Fantasy Town Kit, CC0), sized to the 3 m building grid. Upgraded walls (tier 2+) turn from timber to stone.
- `const PIECE_MODELS := {`

## Functions

### `zombie_look`

```gdscript
static func zombie_look(zombie_type: String) -> Dictionary
```

### `piece_mesh`

```gdscript
static func piece_mesh(piece: String, tier: int) -> Mesh
```

### `wall_mesh`

```gdscript
static func wall_mesh(tier: int) -> Mesh
```

The wall model of a tier, or a timber box when the packs are missing.

### `set_wetness_step`

```gdscript
func set_wetness_step(step: int) -> void
```

A single discrete weather switch updates existing actors; no per-zombie
per-frame material edits. Newly streamed actors inherit _wetness_step.

### `network_jitter_stats`

```gdscript
func network_jitter_stats() -> Dictionary
```

Reusable local diagnostics for network-quality debug overlays.
Server-side privacy and gameplay snapshots are never modified.

### `network_missing_snapshot_estimate`

```gdscript
func network_missing_snapshot_estimate() -> int
```

Native/script read-only counters used by the online profiler.
Scalar getters avoid allocating a full stats Dictionary per sample.

### `network_recovery_hold_remaining`

```gdscript
func network_recovery_hold_remaining() -> int
```

### `update_from`

```gdscript
func update_from(client) -> void
```

### `play_attack`

```gdscript
func play_attack(peer_id: int, weapon_id: String, ranged: bool, direction: Vector2 = Vector2.ZERO) -> void
```

A swing or a shot by another player.

### `warp_model`

```gdscript
func warp_model(model: Node3D, origin: Vector3, weapon_id: String, direction: Vector2, key: String = "") -> void
```

Motion warping: the swinging model glides toward the enemy in front of it.

### `attack_animation`

```gdscript
static func attack_animation(weapon_id: String, ranged: bool) -> String
```

Which animation a weapon uses.

### `play_action_on`

```gdscript
func play_action_on(kind: String, id: int, animation_name: String) -> void
```

Any one-shot animation on a player or zombie drawn here.

### `model_of`

```gdscript
func model_of(kind: String, id: int) -> Node3D
```

A flinch on whoever was struck.
The character model of an entity, or null.

### `play_hit`

```gdscript
func play_hit(kind: String, id: int, heavy: bool = false) -> void
```

### `nearest_hoverable`

```gdscript
func nearest_hoverable(point: Vector3, radius: float) -> Dictionary
```

Nearest zombie / loot bag / player node to a ground point (for hover outlines).

### `nearest_of_kind`

```gdscript
func nearest_of_kind(point: Vector3, kind: String, count: int, radius: float) -> Array[Node3D]
```

Up to `count` nearest visible nodes of one kind ("zombie", "player", "bag") to a point.

### `leap`

```gdscript
func leap(id: int, from: Vector3, to: Vector3) -> void
```

A tree ambusher's drop: an arc from the branch to the ground in front of its prey.

### `telegraph`

```gdscript
func telegraph(id: int, seconds: float, charge: bool) -> void
```

A short red "!" over an infected that is winding up a leap or charge.

_15 private function(s) starting with `_` are not listed._
