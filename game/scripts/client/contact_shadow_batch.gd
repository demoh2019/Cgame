extends Node3D
## Low-overhead grounding shadows for every streamed CharacterModel.
## One GPU MultiMesh draw, no per-NPC MeshInstances or shadow-map passes.
## This is a purely visual fallback; movement/AI/collision stay unchanged.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const GROUP := "aa_grounded_characters"
const UPDATE_PERIOD := 0.08 # ~12.5 CPU updates/s; GPU reuses transforms between updates.
const MAX_INSTANCES := 192
const MAX_RADIUS := 72.0

const PRESETS := [
	{"radius": 28.0, "count": 48, "opacity": 0.45},
	{"radius": 40.0, "count": 80, "opacity": 0.32},
	{"radius": 52.0, "count": 128, "opacity": 0.23},
	{"radius": 70.0, "count": 192, "opacity": 0.16},
]

var _multimesh: MultiMesh
var _instance: MultiMeshInstance3D
var _atmosphere: Node
var _elapsed := 0.0


static func profile(level: int) -> Dictionary:
	return PRESETS[clampi(level, 0, PRESETS.size() - 1)].duplicate(true)


## A deterministic, testable visual priority queue. Actors beyond the draw
## range never enter the GPU buffer; when crowded, the closest get priority.
static func select_actors(actors: Array[Dictionary], camera_position: Vector3,
		level: int, daylight: float, storm: float) -> Array[Dictionary]:
	var p: Dictionary = profile(level)
	var distance_limit: float = float(p["radius"])
	var candidates: Array[Dictionary] = []
	for actor in actors:
		if not bool(actor.get("visible", true)) or not bool(actor.get("alive", true)):
			continue
		if bool(actor.get("submerged", false)):
			continue # Water must not show dark character decals on its surface.
		var position: Vector3 = actor.get("position", Vector3.INF)
		if not position.is_finite():
			continue
		var distance_squared: float = Vector2(position.x, position.z).distance_squared_to(
			Vector2(camera_position.x, camera_position.z))
		if distance_squared > distance_limit * distance_limit:
			continue
		var d: float = sqrt(distance_squared)
		var fade: float = 1.0 - smoothstep(distance_limit * 0.70, distance_limit, d)
		var ambient: float = lerpf(0.38, 1.0, clampf(daylight, 0.0, 1.0))
		var overcast: float = 1.0 - 0.38 * clampf(storm, 0.0, 1.0)
		var opacity: float = clampf(float(p["opacity"]) * fade * ambient * overcast,
			0.0, 1.0)
		if opacity <= 0.001:
			continue
		candidates.append({
			"position": position, "radius": clampf(float(actor.get("radius", 0.82)), 0.35, 2.5),
			"opacity": opacity, "distance_squared": distance_squared,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance_squared"]) < float(b["distance_squared"]))
	if candidates.size() > int(p["count"]):
		candidates.resize(int(p["count"]))
	return candidates


func setup(atmosphere: Node = null) -> void:
	_atmosphere = atmosphere


func _ready() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	var shader := load("res://assets/shaders/contact_shadow.gdshader") as Shader
	var material := ShaderMaterial.new()
	material.shader = shader
	mesh.material = material
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = mesh
	_multimesh.instance_count = MAX_INSTANCES
	_multimesh.visible_instance_count = 0
	_instance = MultiMeshInstance3D.new()
	_instance.name = "InstancedCharacterContactShadows"
	_instance.multimesh = _multimesh
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# One tight camera-relative horizontal region, yet tall enough for cliffs.
	# A correct custom AABB is important: MultiMesh does not cull per actor.
	_instance.custom_aabb = AABB(Vector3(-MAX_RADIUS, -180.0, -MAX_RADIUS),
		Vector3(MAX_RADIUS * 2.0, 480.0, MAX_RADIUS * 2.0))
	add_child(_instance)


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if _elapsed < UPDATE_PERIOD:
		return
	_elapsed = fmod(_elapsed, UPDATE_PERIOD)
	var view_camera: Camera3D = get_viewport().get_camera_3d()
	if view_camera == null:
		_multimesh.visible_instance_count = 0
		return
	var actors: Array[Dictionary] = []
	for member in get_tree().get_nodes_in_group(GROUP):
		if not (member is Node3D):
			continue
		var model: Node3D = member as Node3D
		actors.append({
			"position": model.global_position,
			"visible": model.is_visible_in_tree(),
			"alive": not bool(model.get("_dead")) and int(model.get("_zombie_state")) != 4,
			"submerged": bool(model.get("_swimming")),
			"radius": float(model.get_meta("aa_contact_shadow_radius", 0.82)) *
				(1.5 if bool(model.get("_riding")) else 1.0),
		})
	var sunlight := 1.0
	var storm := 0.0
	if is_instance_valid(_atmosphere):
		sunlight = float(_atmosphere.get("light_level"))
		storm = float(_atmosphere.get("storm"))
	var picked: Array[Dictionary] = select_actors(actors, view_camera.global_position,
		GraphicsQuality.level(), sunlight, storm)
	# Position the one batch around the camera. Transforms are local to this
	# node, not to the origin of a giant open world.
	var origin := Vector3(view_camera.global_position.x, 0.0, view_camera.global_position.z)
	global_position = origin
	for index in picked.size():
		var info: Dictionary = picked[index]
		var at: Vector3 = info["position"]
		var radius: float = float(info["radius"])
		var local: Vector3 = at - origin
		local.y += 0.035 # Tiny depth separation from the walkable ground.
		_multimesh.set_instance_transform(index,
			Transform3D(Basis().scaled(Vector3(radius, 1.0, radius)), local))
		_multimesh.set_instance_custom_data(index,
			Color(float(info["opacity"]), 0.0, 0.0, 0.0))
	_multimesh.visible_instance_count = picked.size()
