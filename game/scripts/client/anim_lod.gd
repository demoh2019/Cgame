extends Node
## Animation update-rate LOD (Unreal URO / Unity culling mode) in GDScript: the fallback for engines without the
## native AnimationLODController. Registered AnimationPlayers run in manual mode and advance every 1st/2nd/4th frame
## by distance, or not at all off-screen / far away, with skipped delta accumulated so animation time stays correct.

const NEAR := 15.0
const MID := 35.0
const FAR := 70.0
const MAX_ACCUMULATED := 0.5
const NEAR_VIEW := 3.0 # Closer than this counts as visible (a point test would flicker at screen edges).

## Distance multiplier per GraphicsQuality level: Performance culls hardest, Ultra keeps full-rate animation farther.
const QUALITY_SCALE := [0.7, 1.0, 1.5, 2.5]

var scale_factor := 1.0
var _entries: Array[Dictionary] = []
var _frame := 0
var _phase := 0


## Frame interval: 1 below near, 2 below mid, 4 below far, 0 (paused) beyond or when not visible.
static func update_interval(distance: float, visible: bool, near: float = NEAR, mid: float = MID, far: float = FAR) -> int:
	if not visible:
		return 0
	if distance < near:
		return 1
	if distance < mid:
		return 2
	if distance < far:
		return 4
	return 0


static func distance_scale(quality_level: int) -> float:
	return QUALITY_SCALE[clampi(quality_level, 0, QUALITY_SCALE.size() - 1)]


## One frame for one animator. Returns [new_accumulator, advance_time]; advance_time < 0 means skip this frame.
static func tick(accumulated: float, delta: float, interval: int, frame: int, phase: int, max_accumulated: float = MAX_ACCUMULATED) -> Array:
	if interval <= 0:
		return [accumulated, -1.0]
	accumulated = minf(accumulated + delta, max_accumulated)
	if (frame + phase) % interval == 0:
		return [0.0, accumulated]
	return [accumulated, -1.0]


func register(animator: AnimationPlayer, model: Node3D) -> void:
	if animator == null or model == null or _index_of(animator) >= 0:
		return
	_entries.append({"animator": animator, "model": model, "accumulated": 0.0, "phase": _phase,
		"mode": animator.callback_mode_process})
	_phase += 1
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func unregister(animator: AnimationPlayer) -> void:
	var index := _index_of(animator)
	if index < 0:
		return
	_release(_entries[index])
	_entries.remove_at(index)


func count() -> int:
	return _entries.size()


func _index_of(animator: AnimationPlayer) -> int:
	for i in _entries.size():
		if _entries[i]["animator"] == animator:
			return i
	return -1


func _release(entry: Dictionary) -> void:
	var animator = entry["animator"]
	if is_instance_valid(animator):
		animator.callback_mode_process = entry["mode"]


func _exit_tree() -> void:
	for entry in _entries:
		_release(entry)


func _process(delta: float) -> void:
	_frame += 1
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var i := 0
	while i < _entries.size():
		var entry: Dictionary = _entries[i]
		var animator = entry["animator"]
		var model = entry["model"]
		if not is_instance_valid(animator) or not is_instance_valid(model):
			_entries.remove_at(i)
			continue
		# Dead or ragdolled models drive their own animation/pose: hand the animator back and stop managing it.
		if bool(model.get("_dead")):
			_release(entry)
			_entries.remove_at(i)
			continue
		i += 1
		if not model.is_inside_tree():
			continue
		var distance := 0.0
		var visible: bool = model.is_visible_in_tree()
		if camera != null:
			var pos: Vector3 = model.global_position
			distance = camera.global_position.distance_to(pos)
			if visible and distance > NEAR_VIEW and not camera.is_position_in_frustum(pos + Vector3.UP):
				visible = false
		var interval := update_interval(distance / scale_factor, visible)
		var result := tick(float(entry["accumulated"]), delta, interval, _frame, int(entry["phase"]))
		entry["accumulated"] = result[0]
		if float(result[1]) >= 0.0:
			animator.advance(float(result[1]))
