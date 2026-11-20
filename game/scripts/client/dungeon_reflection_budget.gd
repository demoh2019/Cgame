extends Node
## Camera-local, GPU-bounded interior reflection captures for procedural dungeons.
## Room markers are cheap Node3Ds, but only High/Ultra Forward+ create actual
## ReflectionProbes. The small pool is reused as the player explores.
## UPDATE_ONCE captures across several frames; NEVER recapture every frame.

const Dungeon = preload("res://scripts/shared/dungeon.gd")
const GROUP := "aa_dungeon_reflection_anchor"
const CHECK_INTERVAL := 0.4
const CAPTURE_COOLDOWN := 1.25
const SWITCH_HYSTERESIS := 3.0

const PRESETS := [
	{"count": 0, "radius": 0.0, "mesh_lod": 4.0},
	{"count": 0, "radius": 0.0, "mesh_lod": 3.0},
	{"count": 1, "radius": 16.0, "mesh_lod": 2.0},
	{"count": 2, "radius": 20.0, "mesh_lod": 1.5},
]

static var _quality: int = 1
var _check_elapsed := 0.0
var _capture_elapsed := CAPTURE_COOLDOWN
var _probes: Array[ReflectionProbe] = []
var _assigned_ids: Array[int] = []


static func settings(level: int, method: String) -> Dictionary:
	var profile: Dictionary = PRESETS[clampi(level, 0, PRESETS.size() - 1)].duplicate(true)
	if method != "forward_plus":
		profile["count"] = 0
		profile["radius"] = 0.0
	return profile


static func configure(level: int) -> void:
	_quality = clampi(level, 0, PRESETS.size() - 1)


## Pure selection function. Existing assignments have a 3 m preference to
## prevent re-capturing on every step across adjacent room boundaries.
static func choose(candidates: Array, count: int, radius: float,
		retained: Array = []) -> Array:
	if count <= 0 or radius <= 0.0:
		return []
	var eligible: Array = []
	for entry in candidates:
		if float(entry.get("distance_sq", INF)) <= radius * radius:
			eligible.append(entry)
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = float(a["distance_sq"])
		var db: float = float(b["distance_sq"])
		if is_equal_approx(da, db):
			return int(a["id"]) < int(b["id"])
		return da < db)
	if eligible.is_empty():
		return []
	var chosen: Array = []
	var minimum: float = sqrt(float(eligible[0]["distance_sq"]))
	var used: Dictionary = {}
	for id in retained:
		for entry in eligible:
			if int(entry["id"]) != int(id):
				continue
			if sqrt(float(entry["distance_sq"])) > minimum + SWITCH_HYSTERESIS:
				break
			if not used.has(id) and chosen.size() < count:
				chosen.append(entry)
				used[id] = true
			break
	for entry in eligible:
		if chosen.size() >= count:
			break
		var id: int = int(entry["id"])
		if not used.has(id):
			chosen.append(entry)
			used[id] = true
	return chosen


static func make_probe(profile: Dictionary) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.name = "DungeonRoomReflection"
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.interior = true
	probe.size = Vector3(Dungeon.ROOM + 0.8, 6.0, Dungeon.ROOM + 0.8)
	probe.blend_distance = 0.8
	probe.intensity = 0.8
	probe.max_distance = 16.0
	probe.mesh_lod_threshold = float(profile["mesh_lod"])
	probe.enable_shadows = false
	# All procedural dungeon geometry uses the standard first render layer.
	# Avoid drawing unrelated effect/utility layers into the cubemap.
	probe.cull_mask = 1
	probe.reflection_mask = 1
	return probe


func _process(delta: float) -> void:
	_check_elapsed += maxf(delta, 0.0)
	_capture_elapsed += maxf(delta, 0.0)
	if _check_elapsed < CHECK_INTERVAL:
		return
	_check_elapsed = fmod(_check_elapsed, CHECK_INTERVAL)
	var method: String = str(RenderingServer.get_current_rendering_method())
	var profile: Dictionary = settings(_quality, method)
	var count: int = int(profile["count"])
	var view: Camera3D = get_viewport().get_camera_3d()
	if count == 0 or view == null:
		_disable_all()
		return
	var eye: Vector3 = view.global_position
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group(GROUP):
		if not (node is Node3D):
			continue
		var anchor := node as Node3D
		var dist_sq: float = eye.distance_squared_to(anchor.global_position)
		if dist_sq <= pow(float(profile["radius"]) + SWITCH_HYSTERESIS, 2.0):
			candidates.append({
				"node": anchor, "id": anchor.get_instance_id(), "distance_sq": dist_sq,
			})
	var selected: Array = choose(candidates, count, float(profile["radius"]), _assigned_ids)
	for i in _probes.size():
		if i >= selected.size() or i >= count:
			_probes[i].visible = false
			_assigned_ids[i] = -1
	for i in selected.size():
		var entry: Dictionary = selected[i]
		var id: int = int(entry["id"])
		# Never move the capture and invalidate its cubemap just to follow the
		# camera. Update only when the player actually changes rooms.
		if i < _probes.size() and _assigned_ids[i] == id:
			_probes[i].visible = true
			continue
		if _capture_elapsed < CAPTURE_COOLDOWN:
			continue
		if i >= _probes.size():
			var probe: ReflectionProbe = make_probe(profile)
			probe.position = (entry["node"] as Node3D).global_position
			add_child(probe)
			_probes.append(probe)
			_assigned_ids.append(id)
		else:
			_probes[i].global_position = (entry["node"] as Node3D).global_position
			_probes[i].mesh_lod_threshold = float(profile["mesh_lod"])
			_probes[i].visible = true
			_assigned_ids[i] = id
		_capture_elapsed = 0.0


func _disable_all() -> void:
	for i in _probes.size():
		_probes[i].visible = false
		_assigned_ids[i] = -1
