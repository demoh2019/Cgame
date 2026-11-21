extends RefCounted
## First-person camera maths for the local survivor. Pure functions so the
## mapping between mouse look, WASD and the server's yaw convention is testable.
##
## Server yaw convention: facing = Vector2(sin(yaw), cos(yaw)) on the XZ plane.
## Input convention (UiAccess.read_move): x = right, y = back (screen down).

const EYE_HEIGHT := 1.62
const CROUCH_EYE_HEIGHT := 1.1
const MOUNTED_EYE_HEIGHT := 2.05
const MAX_PITCH := 1.45
const MOUSE_SENSITIVITY := 0.0025
const JUMP_SECONDS := 0.55
const JUMP_HEIGHT := 0.75


## Forward direction on the XZ plane for a yaw.
static func forward(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


## Right-hand direction on the XZ plane for a yaw.
static func right(yaw: float) -> Vector2:
	return Vector2(-cos(yaw), sin(yaw))


## Turns screen-relative WASD into the world-axis move the server expects.
static func to_world_move(move: Vector2, yaw: float) -> Vector2:
	var world := right(yaw) * move.x + forward(yaw) * -move.y
	return world.limit_length(1.0)


## Applies mouse motion to yaw/pitch. Returns Vector2(yaw, pitch).
static func apply_look(yaw: float, pitch: float, relative: Vector2, sensitivity: float = MOUSE_SENSITIVITY) -> Vector2:
	var new_yaw := wrapf(yaw - relative.x * sensitivity, -PI, PI)
	var new_pitch := clampf(pitch - relative.y * sensitivity, -MAX_PITCH, MAX_PITCH)
	return Vector2(new_yaw, new_pitch)


static func eye_height(crouching: bool, mounted: bool) -> float:
	if mounted:
		return MOUNTED_EYE_HEIGHT
	return CROUCH_EYE_HEIGHT if crouching else EYE_HEIGHT


## Camera transform at the survivor's eyes looking along yaw/pitch.
static func camera_transform(feet: Vector3, yaw: float, pitch: float, height: float) -> Transform3D:
	# A camera looks down -Z; rotating by yaw + PI points it along forward(yaw).
	var basis := Basis(Vector3.UP, yaw + PI) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(basis.orthonormalized(), feet + Vector3(0.0, height, 0.0))


## Vertical camera offset for a cosmetic hop; t < 0 means on the ground.
static func jump_offset(t: float) -> float:
	if t < 0.0 or t >= JUMP_SECONDS:
		return 0.0
	var u: float = t / JUMP_SECONDS
	return 4.0 * JUMP_HEIGHT * u * (1.0 - u)


## A small centred cross that shows where attacks and spells will go.
static func make_crosshair() -> Control:
	var root := Control.new()
	root.name = "Crosshair"
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for bar in [Rect2(-9, -1, 6, 2), Rect2(3, -1, 6, 2), Rect2(-1, -9, 2, 6), Rect2(-1, 3, 2, 6), Rect2(-1, -1, 2, 2)]:
		var piece := ColorRect.new()
		piece.color = Color(1, 1, 1, 0.85)
		piece.position = bar.position
		piece.size = bar.size
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(piece)
	root.visible = false
	return root


# --- First-person feel (Unreal/Unity FPS template parity) -----------------------------------------------------

const FOV_DEFAULT := 75.0
const FOV_MIN := 60.0
const FOV_MAX := 110.0
const NEAR_CLIP := 0.05 # The held item sits ~0.4 m from the eye.
const BOB_STRIDE := 1.9 # Metres per full step cycle (two footfalls).
const BOB_HEIGHT := 0.045
const BOB_SIDE := 0.03
const MAX_ROLL := 0.035 # Radians of strafe lean.
const LAND_DIP := 0.12


## The vertical FOV the first-person camera uses (the isometric view keeps its own narrow lens).
static func fov(setting: float) -> float:
	return clampf(setting if is_finite(setting) else FOV_DEFAULT, FOV_MIN, FOV_MAX)


## Radians per pixel for mouse look from the settings multiplier, negative pitch scale when Y is inverted.
static func look_sensitivity(multiplier: float, invert_y: bool) -> Vector2:
	var s: float = MOUSE_SENSITIVITY * clampf(multiplier if is_finite(multiplier) else 1.0, 0.1, 4.0)
	return Vector2(s, -s if invert_y else s)


## Mouse look with separate horizontal/vertical sensitivity (from look_sensitivity). Returns Vector2(yaw, pitch).
static func apply_look_scaled(yaw: float, pitch: float, relative: Vector2, sensitivity: Vector2) -> Vector2:
	return Vector2(wrapf(yaw - relative.x * sensitivity.x, -PI, PI),
		clampf(pitch - relative.y * sensitivity.y, -MAX_PITCH, MAX_PITCH))


## Advances the step phase (radians) by distance walked; one full cycle per BOB_STRIDE metres.
static func advance_bob_phase(phase: float, speed: float, delta: float) -> float:
	return fmod(phase + maxf(speed, 0.0) * maxf(delta, 0.0) / BOB_STRIDE * TAU, TAU)


## Head bob offset at a step phase: Vector2(side, up). Fades in with speed and is off when `enabled` is false.
static func head_bob(phase: float, speed: float, enabled: bool = true) -> Vector2:
	if not enabled:
		return Vector2.ZERO
	var amount: float = clampf(speed / 4.0, 0.0, 1.4)
	# Two footfalls per cycle: the head dips on each, sways once side to side.
	return Vector2(sin(phase) * BOB_SIDE, -absf(sin(phase)) * BOB_HEIGHT * 2.0 + BOB_HEIGHT) * amount


## Camera roll from sideways speed relative to the view (m/s, + right): lean into the strafe.
static func strafe_roll(lateral_speed: float, enabled: bool = true) -> float:
	if not enabled:
		return 0.0
	return clampf(-lateral_speed / 6.0, -1.0, 1.0) * MAX_ROLL


## Landing dip: a quick drop and spring back over 0.35 s after `t` seconds; 0 outside.
static func landing_dip(t: float) -> float:
	if t < 0.0 or t >= 0.35:
		return 0.0
	var u: float = t / 0.35
	return -LAND_DIP * sin(u * PI) * (1.0 - u)


## Crosshair gap in pixels: tight standing still, opens with speed and in the air.
static func crosshair_spread(speed: float, airborne: bool) -> float:
	return 3.0 + clampf(speed, 0.0, 7.0) * 1.6 + (8.0 if airborne else 0.0)


## Held-item sway: the item lags behind mouse motion (pixels this frame), clamped. Returns Vector2(yaw, pitch) radians.
static func viewmodel_sway(look_relative: Vector2) -> Vector2:
	return Vector2(clampf(-look_relative.x * 0.0009, -0.09, 0.09), clampf(-look_relative.y * 0.0009, -0.07, 0.07))


## Attack animation of the held item at `t` seconds into it: Vector3(back kick m, pitch rad, side swing rad).
## Ranged: a short recoil kick; melee: a wind-up then a fast diagonal slash.
static func attack_pose(t: float, ranged: bool) -> Vector3:
	if t < 0.0:
		return Vector3.ZERO
	if ranged:
		if t >= 0.22:
			return Vector3.ZERO
		var k: float = exp(-t * 18.0) * (1.0 - exp(-t * 90.0))
		return Vector3(0.06 * k * 3.0, 0.18 * k * 3.0, 0.0)
	if t >= 0.45:
		return Vector3.ZERO
	if t < 0.12: # Wind up: raise and pull to the right.
		var w: float = t / 0.12
		return Vector3(-0.02 * w, 0.35 * w, -0.45 * w)
	var s: float = (t - 0.12) / 0.33 # Slash across and settle.
	var slash: float = sin(minf(s * 2.2, 1.0) * PI * 0.5)
	return Vector3(-0.02 * (1.0 - s), lerpf(0.35, -0.5, slash) * (1.0 - s * s), lerpf(-0.45, 0.8, slash) * (1.0 - s * s))


## Shadow-only body for the local survivor in first person: other players still see it, you see its shadow.
static func set_body_shadow_only(model: Node, enabled: bool) -> void:
	if model == null:
		return
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if enabled:
			if not geometry.has_meta("fp_cast_shadow"):
				geometry.set_meta("fp_cast_shadow", geometry.cast_shadow)
			if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif geometry.has_meta("fp_cast_shadow"):
			geometry.cast_shadow = geometry.get_meta("fp_cast_shadow")
			geometry.remove_meta("fp_cast_shadow")


## Re-lays the make_crosshair bars for a gap (px) and a hit-marker strength 0..1 (bars turn red-white and splay).
static func layout_crosshair(root: Control, gap: float, hit: float) -> void:
	if root == null or root.get_child_count() < 5:
		return
	var g: float = gap + hit * 4.0
	var rects := [Rect2(-g - 6, -1, 6, 2), Rect2(g, -1, 6, 2), Rect2(-1, -g - 6, 2, 6), Rect2(-1, g, 2, 6)]
	var tint := Color(1, 1, 1, 0.85).lerp(Color(1.0, 0.25, 0.2, 1.0), clampf(hit, 0.0, 1.0))
	for i in 4:
		var bar := root.get_child(i) as ColorRect
		bar.position = rects[i].position
		bar.size = rects[i].size
		bar.color = tint
	(root.get_child(4) as ColorRect).color = tint
