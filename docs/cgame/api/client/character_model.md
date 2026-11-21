# character_model.gd

> (no header comment)

`res://scripts/client/character_model.gd`

## Constants

- `const CharacterShading = preload("res://scripts/client/character_shading.gd")`
- `const Assets = preload("res://scripts/client/assets.gd")`
- `const RainGear = preload("res://scripts/client/character_rain_gear.gd")`
- `const SkinSSS = preload("res://scripts/client/graphics_skin_scattering.gd")`
- `const Ragdoll = preload("res://scripts/client/ragdoll.gd")`
- `const EngineFeatures = preload("res://scripts/client/engine_features.gd")`
- `const Anim = preload("res://scripts/client/character_anim.gd")`
- `const AnimModifier = preload("res://scripts/client/character_anim_modifier.gd")`
- `const FEMALE_WORKER := ["Female_Peasant_Body", "Female_Peasant_Arms", "Female_Ranger_Legs", "Female_Ranger_Feet"]`
- `const SURVIVOR_LOOKS := {`
- `const ZOMBIE_LOOKS := {"Male": ["Male_Peasant"], "Female": FEMALE_WORKER}`
- `const HEAD_BONES := ["Head", "neck_01"]`
- `const HAIR_COLORS := [Color(0.3, 0.2, 0.13), Color(0.12, 0.1, 0.09), Color(0.45, 0.27, 0.15), Color(0.5, 0.2, 0.1),`
- `const HELD_MODELS := {`
- `const HELD_SCALES := {`
- `const GEAR_PARTS := {`

## Functions

### `setup`

```gdscript
func setup(tint: Color, scale_factor: float, walk_speed: float = 1.0, model_name: String = "", zombie: bool = false, look_seed: int = 0) -> void
```

`model_name` picks a character of the pack ("Orc_Male", "Elf_Female", ...); empty or an unavailable pack
gives the Kenney robot. `scale_factor` is relative to the robot (2.0 is a person), so 2.0 is a normal size for both.
`look_seed` picks the outfit and hair when the clothed survivors are installed (same seed, same look).

### `survivor_sex`

```gdscript
static func survivor_sex(model_name: String) -> String
```

Whether a pack character name should be drawn as a clothed survivor.

### `clear_templates`

```gdscript
static func clear_templates() -> void
```

Frees the cached survivor templates (they live outside the tree); the client calls it when it quits.

### `apply_skin_quality`

```gdscript
func apply_skin_quality(level: int, method: String) -> void
```

Preset switch only; no traversal or duplicate materials inside _process().
Works for new characters already spawned after a previous preset switch.

### `set_wetness_step`

```gdscript
func set_wetness_step(step: int) -> void
```

Called with a discrete weather level, never a continuously changing shader
parameter: 0 restores dry imported PBR, 1-4 use globally cached variants.
A no-op when the tier does not change (the common 60 FPS case).

### `set_tint`

```gdscript
func set_tint(tint: Color) -> void
```

### `set_moving`

```gdscript
func set_moving(moving: bool) -> void
```

### `play_fixed`

```gdscript
func play_fixed(animation_name: String) -> void
```

For people who stand about (settlement survivors): loops one animation forever, whatever its name says.

### `play_action`

```gdscript
func play_action(animation_name: String, speed_scale: float = 1.0) -> void
```

A single action (a swing, a shot) that plays over the movement and then hands control back.

### `set_action_loop`

```gdscript
func set_action_loop(animation_name: String) -> void
```

A looping activity such as chopping; an empty name stops it.

### `set_ground_source`

```gdscript
func set_ground_source(source: Callable) -> void
```

World height source `(x, z) -> y` for foot IK (the terrain's height_at).

### `has_ground_source`

```gdscript
func has_ground_source() -> bool
```

### `set_look_point`

```gdscript
func set_look_point(point: Vector3) -> void
```

World point the head turns toward (camera or threat); Vector3.INF clears it.

### `set_anim_lod`

```gdscript
func set_anim_lod(tier: int) -> void
```

Animation LOD tier from Anim.assign_tiers: 0 full, 1 no IK/look, 2+ reduced update rate and no modifiers.

### `anim_lod_tier`

```gdscript
func anim_lod_tier() -> int
```

### `estimated_full_pose_cost_us`

```gdscript
func estimated_full_pose_cost_us() -> int
```

The next frame's optional full-pose admission estimate combines the real
script modifier duration and native FootPlacement duration when available.
The native timer covers terrain queries + leg solving, not GPU skinning or
core animation playback. Older engines simply report zero native samples.

### `animation_modifier_profile`

```gdscript
func animation_modifier_profile() -> Dictionary
```

Developer diagnostics: last and EMA update costs, by actual modifier.
No scene walks, timers, or allocations are made until explicitly called.

### `weapon_family`

```gdscript
static func weapon_family(item_id: String) -> String
```

The weapon family of an item id: "machete_3" -> "machete".

### `set_gear`

```gdscript
func set_gear(gear: Dictionary) -> void
```

Puts the worn hood, cloak (shoulder mantle) and boots on the survivor's body; a hood hides the hair, boots replace the
outfit's own shoes. Only clothed survivors can show gear.

### `rod_tip`

```gdscript
func rod_tip() -> Vector3
```

The tip of the rod in hand, or INF when there is none.

### `set_weapon`

```gdscript
func set_weapon(item_id: String) -> void
```

Shows the weapon (or tool) in the right hand; an empty or unknown id empties the hand. Cheap to call every frame.

### `start_ragdoll`

```gdscript
func start_ragdoll(push: Vector3) -> PhysicalBoneSimulator3D
```

Hands the body to physics (zombie deaths): stops animation, builds ragdoll bodies,
starts simulation and shoves the torso by `push` (m/s). Null when the rig has no mannequin bones.

### `enable_foot_placement`

```gdscript
func enable_foot_placement(height_at: Callable) -> bool
```

Plants the feet on the terrain with the engine's FootPlacementModifier3D (two-bone leg IK, pelvis drop,
foot-to-ground tilt). `height_at` is Callable(x, z) -> float in world space. A no-op on engine builds
without the class (see game/docs/ENGINE_FOOT_PLACEMENT.md). Returns true when the modifier is active.

### `disable_foot_placement`

```gdscript
func disable_foot_placement() -> void
```

### `set_stance`

```gdscript
func set_stance(crouching: bool, riding: bool, swimming: bool = false) -> void
```

Sneaking low or riding the bike: picked up by update_motion.

### `play_hit`

```gdscript
func play_hit(heavy: bool = false, from_dir: Vector3 = Vector3.ZERO) -> void
```

A flinch when struck (not while already playing an action, dead, or riding).

### `set_dead`

```gdscript
func set_dead(dead: bool) -> void
```

### `set_zombie_state`

```gdscript
func set_zombie_state(state: int) -> void
```

For zombies: the AI state from the snapshot (see Zombie.State).

### `update_motion`

```gdscript
func update_motion(delta: float) -> void
```

Call each frame after the node has moved: works out the speed and picks what to play.

### `status_pulse`

```gdscript
func status_pulse(color: Color) -> void
```

Diablo IV / Hades-style hit flash: every material of this character pops to
a white emissive glow and fades out in ~0.14 s. Reuses the per-character
material duplicates, so other characters are never affected.
Subtle emission cue for a periodic status effect. A real hit always wins.
The periodic scheduler coalesces pulses before calling this method.

### `hit_flash`

```gdscript
func hit_flash(strength: float = 1.0) -> void
```

_17 private function(s) starting with `_` are not listed._
