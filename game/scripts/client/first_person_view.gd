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
