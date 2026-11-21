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
var _native_significance: Object = null


func _ready() -> void:
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var planner: Object = ClassDB.instantiate("SignificanceBudgetPlanner")
		if planner != null and planner.has_method("select_top_stable"):
			_native_significance = planner



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



## Unreal-style significance retention: keep a currently active torch until a
## challenger is meaningfully closer, but never past the hard radius.
## All choices are render-only; gameplay and AI lights remain unchanged.
static func stable_nearest(candidates: Array, maximum: int, radius: float,
		retained: Array = [], hysteresis: float = 4.0, native: Object = null) -> Array:
	if maximum <= 0 or not is_finite(radius) or radius <= 0.0:
		return []
	var limit: int = mini(maximum, 128)
	var bonus: float = clampf(hysteresis, 0.0, radius) if is_finite(hysteresis) else 0.0
	var eligible: Array = []
	var distances := PackedFloat64Array()
	var ids := PackedInt64Array()
	var previous := PackedInt64Array()
	for old_id in retained:
		if int(old_id) > 0 and previous.size() < 128:
			previous.append(int(old_id))
	for entry in candidates:
		var dsq: float = float(entry.get("distance_sq", INF))
		var id: int = int(entry.get("id", 0))
		if not is_finite(dsq) or dsq < 0.0 or dsq > radius * radius or id <= 0:
			continue
		var distance: float = sqrt(dsq)
		var score: float = maxf(0.0, distance - (bonus if retained.has(id) else 0.0))
		var record: Dictionary = {"entry": entry, "distance": distance, "score": score, "id": id}
		eligible.append(record)
		distances.append(distance)
		ids.append(id)
	if eligible.is_empty():
		return []
	if native != null and native.has_method("select_top_stable"):
		var indices: PackedInt32Array = native.call("select_top_stable",
			distances, ids, previous, limit, radius, bonus)
		if not indices.is_empty():
			var selected: Array = []
			for index in indices:
				selected.append(eligible[index]["entry"])
			return selected
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] < b["score"]
		if a["distance"] != b["distance"]:
			return a["distance"] < b["distance"]
		if a["id"] != b["id"]:
			return a["id"] < b["id"]
		return false)
	var count: int = mini(limit, eligible.size())
	var result: Array = []
	for i in range(count):
		result.append(eligible[i]["entry"])
	return result


## Camera/split-screen aware significance: bounded native world selection with
## stable IDs, while stock Godot follows the same nearest-observer scoring.
## This only changes cosmetic torch activation, never damage or enemy vision.
static func stable_world(candidates: Array, observers: PackedVector3Array,
		maximum: int, radius: float, retained: Array = [],
		hysteresis: float = 4.0, native: Object = null) -> Array:
	if (maximum <= 0 or not is_finite(radius) or radius <= 0.0
			or observers.is_empty() or observers.size() > 16):
		return []
	for eye in observers:
		if not eye.is_finite():
			return []
	var previous := PackedInt64Array()
	var old_ids: Dictionary = {}
	for raw_id in retained:
		var old_id: int = int(raw_id)
		if old_id > 0 and not old_ids.has(old_id) and previous.size() < 128:
			previous.append(old_id)
			old_ids[old_id] = true
	var records: Array = []
	var positions := PackedVector3Array()
	var ids := PackedInt64Array()
	var priorities := PackedByteArray()
	var seen: Dictionary = {}
	for entry in candidates:
		if positions.size() >= 16384:
			break
		var id: int = int(entry.get("id", 0))
		var point: Vector3 = entry.get("position", Vector3(INF, INF, INF))
		if id <= 0 or not point.is_finite() or seen.has(id):
			continue
		seen[id] = true
		records.append(entry)
		positions.append(point)
		ids.append(id)
		priorities.append(0) # All torches are cosmetic and in one priority tier.
	if records.is_empty():
		return []
	var bonus: float = clampf(hysteresis, 0.0, radius) if is_finite(hysteresis) else 0.0
	var selected: Array = []
	if native != null and native.has_method("select_world_priority_stable"):
		var indices: PackedInt32Array = native.call("select_world_priority_stable",
			positions, observers, priorities, ids, previous,
			mini(maximum, 128), radius, bonus)
		for index in indices:
			var record: Dictionary = records[index].duplicate()
			var distance_sq: float = INF
			var position: Vector3 = record["position"]
			for eye in observers:
				distance_sq = minf(distance_sq, position.distance_squared_to(eye))
			record["distance_sq"] = distance_sq
			selected.append(record)
		return selected
	var eligible: Array = []
	for record in records:
		var distance_sq: float = INF
		var position: Vector3 = record["position"]
		for eye in observers:
			distance_sq = minf(distance_sq, position.distance_squared_to(eye))
		if is_finite(distance_sq) and distance_sq <= radius * radius:
			var entry: Dictionary = record.duplicate()
			entry["distance_sq"] = distance_sq
			eligible.append(entry)
	return stable_nearest(eligible, mini(maximum, 128), radius, retained, bonus)


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
	var observers := PackedVector3Array()
	observers.append(camera.global_position)
	# Optional observer nodes cover additional local viewports without
	# allocating separate light pools. A global maximum of 16 stays bounded.
	for observer in get_tree().get_nodes_in_group("aa_dungeon_light_observer"):
		if observers.size() >= 16:
			break
		if observer is Node3D and observer.is_inside_tree():
			observers.append((observer as Node3D).global_position)
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group(GROUP):
		if not (node is OmniLight3D):
			continue
		var light := node as OmniLight3D
		if not is_instance_valid(light):
			continue
		# Cheap broad-phase; distant streamed chunks do not enter the native
		# ranking batch and cannot consume its 16,384-candidate bound.
		var point: Vector3 = light.global_position
		var nearby := false
		for eye in observers:
			if point.distance_squared_to(eye) <= radius * radius:
				nearby = true
				break
		if not nearby:
			continue
		candidates.append({"node": light, "position": point,
			"id": light.get_instance_id()})
	var renderer: String = str(RenderingServer.get_current_rendering_method())
	var previous: Array = []
	for torch in _active:
		if is_instance_valid(torch):
			previous.append(torch.get_instance_id())
	var selected: Array = stable_world(candidates, observers,
		effective_max(_quality, renderer), radius, previous, 4.0, _native_significance)
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
