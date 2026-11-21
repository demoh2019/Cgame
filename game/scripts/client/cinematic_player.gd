extends Node
## Plays a cinematic_sequence.gd timeline onto bound nodes.
## Bindings map track / camera names to Node3D / Camera3D / AnimationPlayer.
## Float tracks named "fov", "focus_distance", "aperture", "exposure" drive the
## current camera (fov, and DOF/exposure via CameraAttributesPractical when
## present); "binding:property" drives any property of a bound node.

signal event_fired(event_name: String, args: Array)
signal finished

var sequence: RefCounted = null
var bindings: Dictionary = {}
var time: float = 0.0
var loop: bool = false
var time_scale: float = 1.0
var playing: bool = false
var paused: bool = false
var blend_seconds: float = 0.0
var _current_camera: String = ""


func play(seq: RefCounted, bind: Dictionary) -> void:
	sequence = seq
	bindings = bind
	time = 0.0
	playing = true
	paused = false
	_current_camera = ""
	_apply()


func stop() -> void:
	playing = false


func pause() -> void:
	paused = true


func resume() -> void:
	paused = false


func seek(t: float) -> void:
	if sequence == null:
		return
	time = clampf(t, 0.0, float(sequence.get("length")))
	_apply()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if sequence == null or not playing or paused:
		return
	var length: float = sequence.get("length")
	var old: float = time
	var nt: float = old + delta * time_scale
	if nt >= length:
		if loop and length > 0.0:
			nt = fmod(nt, length)
			_fire(old, nt)  # wraps: [old, length) + [0, nt)
			time = nt
			_apply()
		else:
			_fire(old, INF)
			time = length
			_apply()
			playing = false
			finished.emit()
		return
	if nt < 0.0:
		nt = 0.0
	if nt > old:
		_fire(old, nt)
	time = nt
	_apply()


func _fire(t0: float, t1: float) -> void:
	var evs: Array = sequence.call("events_between", t0, t1)
	for e in evs:
		var ed: Dictionary = e
		event_fired.emit(String(ed["name"]), ed["args"] as Array)
	var anims: Array = sequence.call("animations_between", t0, t1)
	for a in anims:
		var ad: Dictionary = a
		var target: Variant = bindings.get(String(ad["target"]), null)
		if target is AnimationPlayer:
			(target as AnimationPlayer).play(StringName(String(ad["animation"])))


func _apply() -> void:
	var tts: Dictionary = sequence.get("transform_tracks")
	for track in tts.keys():
		var node: Variant = bindings.get(String(track), null)
		if node is Node3D and is_instance_valid(node as Node3D):
			(node as Node3D).transform = sequence.call("sample_transform", String(track), time)
	_update_camera()
	var fts: Dictionary = sequence.get("float_tracks")
	for track in fts.keys():
		_apply_float(String(track), float(sequence.call("sample_float", String(track), time)))


func _update_camera() -> void:
	var shot: Dictionary = sequence.call("active_shot", time)
	if shot.is_empty():
		return
	var cam_name: String = shot["camera"]
	if cam_name == _current_camera:
		return
	_current_camera = cam_name
	for s in (sequence.get("shots") as Array):
		var other: Variant = bindings.get(String((s as Dictionary)["camera"]), null)
		if other is Camera3D and String((s as Dictionary)["camera"]) != cam_name:
			(other as Camera3D).current = false
	var cam: Variant = bindings.get(cam_name, null)
	if cam is Camera3D:
		(cam as Camera3D).current = true


func current_camera() -> Camera3D:
	var cam: Variant = bindings.get(_current_camera, null)
	return cam as Camera3D if cam is Camera3D else null


func _apply_float(track: String, value: float) -> void:
	var colon: int = track.find(":")
	if colon >= 0:
		var target: Variant = bindings.get(track.substr(0, colon), null)
		if target is Object and is_instance_valid(target as Object):
			(target as Object).set(track.substr(colon + 1), value)
		return
	var cam: Camera3D = current_camera()
	if cam == null:
		return
	if track == "fov":
		cam.fov = value
		return
	var attrs: CameraAttributes = cam.attributes
	if attrs == null:
		return
	if attrs is CameraAttributesPractical:
		var p: CameraAttributesPractical = attrs
		match track:
			"focus_distance":
				p.dof_blur_far_distance = value
				p.dof_blur_near_distance = maxf(0.01, value * 0.5)
			"aperture", "dof":
				p.dof_blur_amount = value
			"exposure":
				p.exposure_multiplier = value
	elif track == "exposure":
		attrs.exposure_multiplier = value
