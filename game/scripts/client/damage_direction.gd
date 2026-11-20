extends CanvasLayer
## Damage direction indicator (Call of Duty / Fortnite): a red arc at the screen
## edge points to whoever just hit you, relative to the camera, and fades out.
## Uses only the server's hit event ("by" attacker id) and snapshot positions.

const LIFE := 1.3
const MAX_ARCS := 4

var camera: Camera3D
var _arcs: Array[Dictionary] = [] # {"world": Vector3, "age": float, "strength": float}
var _canvas: Control


## Screen angle (radians, 0 = up/ahead, clockwise) of `target` from `me` for a camera basis.
static func screen_angle(me: Vector3, target: Vector3, cam_basis: Basis) -> float:
	var d := target - me
	var right := cam_basis.x
	var forward := -cam_basis.z
	forward.y = 0.0
	right.y = 0.0
	if forward.length_squared() < 1e-6:
		forward = cam_basis.y
		forward.y = 0.0
	return atan2(d.dot(right.normalized()), d.dot(forward.normalized()))


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_arcs)
	add_child(_canvas)


func on_hit(attacker_world: Vector3, damage: float) -> void:
	if _arcs.size() >= MAX_ARCS:
		_arcs.pop_front()
	_arcs.append({"world": attacker_world, "age": 0.0, "strength": clampf(damage / 30.0, 0.35, 1.0)})


func update_view(me: Vector3, delta: float) -> void:
	for i in range(_arcs.size() - 1, -1, -1):
		_arcs[i]["age"] = float(_arcs[i]["age"]) + delta
		if float(_arcs[i]["age"]) >= LIFE:
			_arcs.remove_at(i)
	_canvas.set_meta("me", me)
	_canvas.queue_redraw()


func _draw_arcs() -> void:
	if camera == null or _arcs.is_empty():
		return
	var me: Vector3 = _canvas.get_meta("me", Vector3.ZERO)
	var size := _canvas.size
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.36
	for arc in _arcs:
		var a: float = screen_angle(me, arc["world"], camera.global_transform.basis)
		var t: float = float(arc["age"]) / LIFE
		var alpha: float = (1.0 - t * t) * float(arc["strength"])
		# Godot's draw_arc: 0 rad = +X (right), clockwise in screen space; "up" is -PI/2.
		var mid: float = a - PI * 0.5
		_canvas.draw_arc(center, radius, mid - 0.32, mid + 0.32, 24, Color(1.0, 0.15, 0.1, 0.75 * alpha), 14.0, true)
		_canvas.draw_arc(center, radius + 9.0, mid - 0.2, mid + 0.2, 16, Color(1.0, 0.5, 0.4, 0.5 * alpha), 4.0, true)
