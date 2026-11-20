extends RefCounted
## Pure, unit-testable helpers for procedural character animation (foot IK, look-at, lean, breathing, additive
## flinch, upper-body layering, animation LOD). The runtime driver is character_anim_modifier.gd.

const UP := Vector3.UP
const CombatAnimationPriority = preload("res://scripts/client/combat_animation_priority.gd")

# --- Animation LOD / crowd budget (Unreal URO / Unity Animator Culling) --------------------------------------------------

## How many characters may run the full procedural stack (IK, look-at) per quality tier 0..3.
static func full_budget(quality: int) -> int:
	return [0, 4, 8, 14][clampi(quality, 0, 3)]


## 0 full rate + modifiers, 1 full rate no IK, 2 half rate, 3 quarter rate, 4 eighth rate.
static func lod_tier(distance: float) -> int:
	if distance < 22.0:
		return 0
	if distance < 38.0:
		return 1
	if distance < 60.0:
		return 2
	if distance < 90.0:
		return 3
	return 4


## Seconds between animation updates of a tier (0 = every frame).
static func lod_interval(tier: int) -> float:
	return [0.0, 0.0, 1.0 / 30.0, 1.0 / 15.0, 1.0 / 8.0][clampi(tier, 0, 4)]


## Assigns a tier to each character from its distance. Only the nearest `budget` characters may be tier 0;
## the rest of the near crowd is demoted to tier 1. Returns tiers in the order of `distances`.
static func assign_tiers(distances: Array, budget: int) -> PackedInt32Array:
	var order: Array = range(distances.size())
	order.sort_custom(func(a, b): return float(distances[a]) < float(distances[b]))
	var out := PackedInt32Array()
	out.resize(distances.size())
	var granted := 0
	for index in order:
		var tier := lod_tier(float(distances[index]))
		if tier == 0:
			if granted < budget:
				granted += 1
			else:
				tier = 1
		out[index] = tier
	return out


# --- Smoothing / springs --------------------------------------------------------------------------------------------------

## Exponential smoothing independent of frame rate.
static func smooth(current: float, target: float, delta: float, rate: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * maxf(delta, 0.0)))


## Moves a playback rate toward its target at most `max_rate` per second (no pops when the speed bracket changes).
static func smooth_rate(current: float, target: float, delta: float, max_rate: float = 4.0) -> float:
	return move_toward(current, target, max_rate * maxf(delta, 0.0))


## One semi-implicit spring-damper step; returns [position, velocity].
static func spring_step(x: float, v: float, target: float, stiffness: float, damping: float, delta: float) -> Array:
	v += ((target - x) * stiffness - v * damping) * delta
	x += v * delta
	return [x, v]


# --- Procedural body motion -----------------------------------------------------------------------------------------------

## Lean into a turn: [roll, pitch] radians for the spine. `yaw_rate` rad/s (positive = turning left), `speed` m/s.
## Roll toward the inside of the turn, pitch forward with speed.
static func lean_angles(yaw_rate: float, speed: float) -> Vector2:
	var strength := clampf(speed / 4.0, 0.0, 1.2)
	var roll := clampf(-yaw_rate * 0.05 * strength, -0.17, 0.17)
	var pitch := clampf(speed * 0.012, 0.0, 0.08)
	return Vector2(roll, pitch)


## Idle breathing: chest pitch in radians at time t, fading out while moving (`moving_weight` 0..1).
static func breath_angle(t: float, moving_weight: float) -> float:
	return sin(t * TAU * 0.28) * 0.016 * (1.0 - clampf(moving_weight, 0.0, 1.0))


## Yaw/pitch (radians, clamped) needed to look along `target_dir` for a body whose basis is `body_basis`
## (+Z forward, +Y up). Targets behind the body stay clamped at the limit, scaled down to zero when directly behind.
static func look_angles(body_basis: Basis, target_dir: Vector3, max_yaw: float, max_pitch: float) -> Vector2:
	if target_dir.length_squared() < 0.0001:
		return Vector2.ZERO
	var d := body_basis.orthonormalized().inverse() * target_dir.normalized()
	var yaw := atan2(d.x, d.z)
	var pitch := asin(clampf(d.y, -1.0, 1.0))
	var behind := clampf((absf(yaw) - PI * 0.6) / (PI * 0.4), 0.0, 1.0) # past ~108 degrees, ease back to forward
	var fade := 1.0 - behind
	return Vector2(clampf(yaw, -max_yaw, max_yaw) * fade, clampf(pitch, -max_pitch, max_pitch) * fade)


## World-space rotation for a yaw/pitch look pair, expressed around the body frame.
static func look_rotation(body_basis: Basis, angles: Vector2) -> Quaternion:
	var local := Quaternion(UP, angles.x) * Quaternion(Vector3.RIGHT, -angles.y)
	var b := Quaternion(body_basis.orthonormalized())
	return b * local * b.inverse()


## Rotation conjugated into world space: roll about the body forward axis, pitch about its lateral axis.
static func lean_rotation(body_basis: Basis, roll: float, pitch: float) -> Quaternion:
	var local := Quaternion(Vector3.BACK, roll) * Quaternion(Vector3.RIGHT, pitch)
	var b := Quaternion(body_basis.orthonormalized())
	return b * local * b.inverse()


# --- Foot IK ---------------------------------------------------------------------------------------------------------------

## 1 while a foot is on the ground, 0 once it lifted `lift` metres above its planted height (swing phase).
static func contact_weight(height_above_plant: float, lift: float = 0.14) -> float:
	return 1.0 - clampf(height_above_plant / lift, 0.0, 1.0)


## Pelvis shift (<= 0 normally): the hips follow the lower foot target so neither leg overextends; clamped.
static func pelvis_offset(left_delta: float, right_delta: float, limit: float = 0.35) -> float:
	return clampf(minf(minf(left_delta, right_delta), 0.0), -limit, 0.0)


## Surface normal from a centre sample and two neighbours `step` metres along +X and +Z.
static func ground_normal(h0: float, hx: float, hz: float, step: float) -> Vector3:
	return Vector3(-(hx - h0) / step, 1.0, -(hz - h0) / step).normalized()


## Analytic two-bone IK. Hip `a`, knee `b`, ankle `c`, desired ankle `target`. Returns [new_knee, new_ankle]; bone
## lengths are kept, the knee bends toward its original side, unreachable targets are clamped to full extension.
static func solve_knee(a: Vector3, b: Vector3, c: Vector3, target: Vector3) -> Array:
	var l1 := (b - a).length()
	var l2 := (c - b).length()
	var to_target := target - a
	var dir := to_target.normalized() if to_target.length_squared() > 0.000001 else (c - a).normalized()
	var d := clampf(to_target.length(), absf(l1 - l2) + 0.0005, l1 + l2 - 0.0005)
	var along := (l1 * l1 + d * d - l2 * l2) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var bend := (b - a) - dir * (b - a).dot(dir)
	if bend.length_squared() < 0.000001:
		bend = (b - a).cross(Vector3.RIGHT)
	if bend.length_squared() < 0.000001:
		bend = Vector3.BACK
	return [a + dir * along + bend.normalized() * h, a + dir * d]


# --- Upper-body layering (Unity Avatar Mask / Unreal Layered Blend Per Bone) -----------------------------------------------

const UPPER_PREFIXES := ["spine", "neck", "head", "clavicle", "upperarm", "lowerarm", "hand", "thumb", "index", "middle",
	"ring", "pinky", "weapon"]


static func is_upper_body_bone(bone: String) -> bool:
	var lower := bone.to_lower()
	for prefix in UPPER_PREFIXES:
		if lower.begins_with(prefix):
			return true
	return false


## The bone a skeleton track path points at ("Armature/Skeleton3D:upperarm_l" -> "upperarm_l"); "" for non-bone paths.
static func track_bone(path: NodePath) -> String:
	var subname := path.get_concatenated_subnames()
	return subname.get_slice(":", 0) if subname != "" else ""


## Copy of `animation` that only drives upper-body bones (loop mode kept). Used by a second AnimationPlayer layered
## over locomotion so a swing plays while the legs keep walking.
static func upper_body_copy(animation: Animation) -> Animation:
	var copy := animation.duplicate() as Animation
	for i in range(copy.get_track_count() - 1, -1, -1):
		var bone := track_bone(copy.track_get_path(i))
		if bone == "" or not is_upper_body_bone(bone):
			copy.remove_track(i)
	return copy


## Whether an action clip should be layered over locomotion rather than replace it.
static func layerable(animation_name: String, moving: bool, zombie: bool) -> bool:
	if not moving or zombie:
		return false
	for prefix in ["Sword", "Melee", "Punch", "Pistol", "Spell", "Throw", "Interact"]:
		if animation_name.begins_with(prefix):
			return true
	return false


# --- Crowd pass ----------------------------------------------------------------------------------------------------------

## Once per frame over every live CharacterModel: distance LOD tiers within the crowd budget, terrain source for foot
## IK, and a camera look-at for the closest few. `models` are CharacterModel nodes.
static func apply_crowd(models: Array, camera: Camera3D, quality: int, ground: Callable) -> void:
	if camera == null or models.is_empty():
		return
	var cam := camera.global_position
	var distances: Array = []
	for model in models:
		distances.append(model.global_position.distance_to(cam))
	var tiers := assign_tiers(distances, full_budget(quality))
	# Stock Godot fallback: maintain full-rate poses (without procedural IK)
	# for a bounded number of visible critical enemies. Native Cgame owns
	# its own priority scheduler and must not be driven twice.
	var preferred: Array[int] = []
	for i in models.size():
		var model = models[i]
		if bool(model.get("external_anim_lod")) or not bool(
				model.get_meta("aa_combat_animation_priority", false)):
			continue
		if float(distances[i]) < 90.0 and camera.is_position_in_frustum(
				model.global_position + Vector3.UP):
			preferred.append(i)
	preferred.sort_custom(func(a: int, b: int) -> bool:
		return float(distances[a]) < float(distances[b]))
	var slots: int = mini(CombatAnimationPriority.slots(quality), preferred.size())
	for j in slots:
		tiers[preferred[j]] = mini(tiers[preferred[j]], 1)
	for i in models.size():
		var model = models[i]
		if ground.is_valid() and not model.has_ground_source():
			model.set_ground_source(ground)
		model.set_anim_lod(tiers[i])
		model.set_look_point(cam if tiers[i] == 0 and distances[i] < 12.0 else Vector3.INF)
