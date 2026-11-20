extends Node
## Global, render-only budget for room torches across all streamed dungeon chunks.
## Forward+/Compatibility both have limits for many overlapping OmniLight3D nodes.
## One manager selects the nearest lights instead of each chunk spending its own budget.

const GROUP := "aa_dungeon_torches"
const UPDATE_INTERVAL := 0.13
const FADE_DISTANCE := 7.0
const DungeonTorchCookie = preload("res://scripts/client/dungeon_torch_cookie.gd")

const PRESETS := [
	{"max_lights": 3, "radius": 28.0, "flicker": 0.035, "shadow_lights": 0},
	{"max_lights": 6, "radius": 44.0, "flicker": 0.060, "shadow_lights": 0},
	{"max_lights": 10, "radius": 62.0, "flicker": 0.085, "shadow_lights": 1},
	{"max_lights": 16, "radius": 84.0, "flicker": 0.110, "shadow_lights": 2},
]

static var _quality := 1
var _elapsed := 0.0
var _active: Array[OmniLight3D] = []


static func settings(quality: int) -> Dictionary:
	return PRESETS[clampi(quality, 0, PRESETS.size() - 1)].duplicate(true)


static func configure(quality: int) -> void:
	_quality = clampi(quality, 0, PRESETS.size() - 1)


## OpenGL Compatibility has a smaller simultaneous light budget than Forward+.
static func effective_max(quality: int, backend: String) -> int:
	var requested: int = int(settings(quality)["max_lights"])
	return mini(requested, 8) if backend != "forward_plus" else requested


## Pure selector; "node" is intentionally opaque so unit tests need no GPU or scene.
## Equal-distance ties are stable within a session to avoid flickering light selection.
static func nearest(candidates: Array, maximum: int, radius: float) -> Array:
	if maximum <= 0 or radius <= 0.0:
		return []
	var radius_squared := radius * radius
	var eligible: Array = []
	for entry in candidates:
		if float(entry.get("distance_sq", INF)) <= radius_squared:
			eligible.append(entry)
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = float(a["distance_sq"])
		var db: float = float(b["distance_sq"])
		if is_equal_approx(da, db):
			return int(a.get("id", 0)) < int(b.get("id", 0))
		return da < db)
	if eligible.size() > maximum:
		eligible.resize(maximum)
	return eligible


## Soft fading keeps the room light from popping at the budget range.
static func intensity(distance: float, radius: float, time: float,
		seed: float, flicker_amount: float) -> float:
	if radius <= 0.0 or distance >= radius:
		return 0.0
	var fade: float = 1.0 - smoothstep(maxf(0.0, radius - FADE_DISTANCE), radius, distance)
	var flame: float = 1.0 + flicker_amount * (
		0.6 * sin(time * 3.7 + seed) +
		0.4 * sin(time * 8.1 + seed * 1.73))
	return clampf(fade * flame, 0.0, 1.2)


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if _elapsed < UPDATE_INTERVAL:
		return
	_elapsed = fmod(_elapsed, UPDATE_INTERVAL)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var profile: Dictionary = settings(_quality)
	var radius: float = float(profile["radius"])
	var candidates: Array = []
	var eye: Vector3 = camera.global_position
	for node in get_tree().get_nodes_in_group(GROUP):
		if not (node is OmniLight3D):
			continue
		var light := node as OmniLight3D
		if not is_instance_valid(light):
			continue
		var dist_sq: float = eye.distance_squared_to(light.global_position)
		if dist_sq < radius * radius:
			candidates.append({"node": light, "distance_sq": dist_sq, "id": light.get_instance_id()})
	var renderer: String = str(RenderingServer.get_current_rendering_method())
	var selected: Array = nearest(candidates, effective_max(_quality, renderer), radius)
	var keep: Dictionary = {}
	var seconds: float = float(Time.get_ticks_msec()) * 0.001
	var updated: Array[OmniLight3D] = []
	var allow_shadows: bool = renderer == "forward_plus"
	for entry in selected:
		var light: OmniLight3D = entry["node"]
		keep[light.get_instance_id()] = true
		var distance: float = sqrt(float(entry["distance_sq"]))
		var power: float = intensity(distance, radius, seconds,
			float(light.get_meta("aa_flame_seed", 0.0)), float(profile["flicker"]))
		light.light_energy = 2.2 * power
		# Only the closest one/two torches cast expensive realtime shadows,
		# and only on Forward+. Compatibility remains shadowless for local lights.
		var cast: bool = allow_shadows and \
			updated.size() < int(profile["shadow_lights"]) and power > 0.25 and \
			distance <= DungeonTorchCookie.shadow_distance(_quality)
		if light.shadow_enabled != cast:
			light.shadow_enabled = cast
		# Godot native 360-degree cookie is bound only to already-shadowed
		# torches. Reuses one tiny image for the entire streamed dungeon.
		DungeonTorchCookie.apply(light, _quality, renderer, cast)
		# Use engine-side distance fade so border lights also disappear gradually.
		if not light.distance_fade_enabled:
			light.distance_fade_enabled = true
		var fade_begin: float = maxf(0.0, radius - FADE_DISTANCE)
		if light.distance_fade_begin != fade_begin:
			light.distance_fade_begin = fade_begin
		if light.distance_fade_length != FADE_DISTANCE:
			light.distance_fade_length = FADE_DISTANCE
		light.visible = true
		updated.append(light)
	for light in _active:
		if is_instance_valid(light) and not keep.has(light.get_instance_id()):
			light.visible = false
			light.shadow_enabled = false
			DungeonTorchCookie.apply(light, _quality, renderer, false)
	_active = updated
