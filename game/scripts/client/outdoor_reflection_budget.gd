extends Node
## Outdoor local reflection captures for shiny structures, wet stone and metal.
## One world-wide camera-local pool; chunks provide lightweight marker nodes,
## never a ReflectionProbe each. Captures render once on location changes.
## The sky remains the fallback outside probe influence and on low-end GPUs.

const GROUP := "aa_outdoor_reflection_anchor"
const CHECK_INTERVAL := 0.45
const CAPTURE_COOLDOWN := 1.6
# Similar to HDRP On Demand captures: avoid live six-face redraws on every
# frame when day/night or rain alters the environment. At most one shared
# cubemap is invalidated every 18 seconds, only on a meaningful change.
const WEATHER_RECAPTURE_INTERVAL := 18.0
const DAYLIGHT_RECAPTURE_DELTA := 0.17
const STORM_RECAPTURE_DELTA := 0.26
const SWITCH_HYSTERESIS := 5.0
const SITE_KINDS := {
	"village": true, "farm": true, "depot": true, "outpost": true,
	"city": true, "dock": true, "lighthouse": true, "tower": true,
}
const PRESETS := [
	{"count": 0, "radius": 0.0, "max_distance": 0.0, "mesh_lod": 4.0},
	{"count": 0, "radius": 0.0, "max_distance": 0.0, "mesh_lod": 3.0},
	{"count": 1, "radius": 44.0, "max_distance": 32.0, "mesh_lod": 2.4},
	{"count": 2, "radius": 60.0, "max_distance": 42.0, "mesh_lod": 1.5},
]

static var _quality := 1
## Set by online_main when creating the one global reflection manager.
## Use the same smoothed atmospheric daylight/storm as the sky and PBR.
var atmosphere: Node3D
var _weather_at_capture: Array[Vector2] = []
var _weather_refresh_elapsed := WEATHER_RECAPTURE_INTERVAL
var _elapsed := 0.0
var _capture_elapsed := CAPTURE_COOLDOWN
var _probes: Array[ReflectionProbe] = []
var _assigned: Array[int] = []


static func configure(level: int) -> void:
	_quality = clampi(level, 0, PRESETS.size() - 1)


static func settings(level: int, method: String) -> Dictionary:
	var result: Dictionary = PRESETS[clampi(level, 0, PRESETS.size() - 1)].duplicate(true)
	if method != "forward_plus":
		result["count"] = 0
		result["radius"] = 0.0
	return result


## Never spawn duplicates at site edges: only the chunk containing the site's
## center owns its marker. The server and client use identical world cells.
static func belongs_to_chunk(site_x: float, site_z: float,
		origin: Vector2, chunk_size: float) -> bool:
	return is_finite(site_x) and is_finite(site_z) and chunk_size > 0.0 			and site_x >= origin.x and site_x < origin.x + chunk_size 			and site_z >= origin.y and site_z < origin.y + chunk_size


## Nearer captures win, but retain an assigned site until a different one
## is at least 5m closer. No rapid recaptures while moving through a town.
static func choose(candidates: Array, count: int, radius: float,
		retained: Array = []) -> Array:
	if count <= 0 or radius <= 0.0:
		return []
	var eligible: Array = []
	for entry in candidates:
		if float(entry.get("distance_sq", INF)) <= radius * radius:
			eligible.append(entry)
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a["distance_sq"]), float(b["distance_sq"])):
			return int(a["id"]) < int(b["id"])
		return float(a["distance_sq"]) < float(b["distance_sq"]))
	if eligible.is_empty():
		return []
	var chosen: Array = []
	var closest: float = sqrt(float(eligible[0]["distance_sq"]))
	var used: Dictionary = {}
	for old_id in retained:
		for entry in eligible:
			if int(entry["id"]) != int(old_id):
				continue
			if sqrt(float(entry["distance_sq"])) <= closest + SWITCH_HYSTERESIS 					and chosen.size() < count and not used.has(old_id):
				chosen.append(entry)
				used[old_id] = true
			break
	for entry in eligible:
		if chosen.size() >= count:
			break
		var id: int = int(entry["id"])
		if not used.has(id):
			chosen.append(entry)
			used[id] = true
	return chosen


## Pure scheduler: invalid or unavailable weather never forces cubemaps.
static func weather_signature(daylight: float, storm: float) -> Vector2:
	if not is_finite(daylight) or not is_finite(storm):
		return Vector2(-1.0, -1.0)
	return Vector2(clampf(daylight, 0.0, 1.0), clampf(storm, 0.0, 1.0))


static func weather_changed(captured: Vector2, current: Vector2) -> bool:
	if not captured.is_finite() or not current.is_finite():
		return false
	if minf(captured.x, captured.y) < 0.0 or minf(current.x, current.y) < 0.0:
		return false
	return absf(captured.x - current.x) >= DAYLIGHT_RECAPTURE_DELTA or \
		absf(captured.y - current.y) >= STORM_RECAPTURE_DELTA


static func make_probe(profile: Dictionary) -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.name = "OutdoorArchitectureReflection"
	probe.visible = false
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.interior = false # Preserve daylight/moonlight sky radiance.
	probe.size = Vector3(26.0, 12.0, 26.0)
	probe.blend_distance = 3.5
	probe.intensity = 0.7 # Blend gently with sky IBL and existing SSR.
	probe.max_distance = float(profile["max_distance"])
	probe.mesh_lod_threshold = float(profile["mesh_lod"])
	probe.enable_shadows = false # Skip six cubemap-face shadow-map renders.
	probe.cull_mask = 1
	probe.reflection_mask = 1
	return probe


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	_capture_elapsed += maxf(delta, 0.0)
	_weather_refresh_elapsed += maxf(delta, 0.0)
	if _elapsed < CHECK_INTERVAL:
		return
	_elapsed = fmod(_elapsed, CHECK_INTERVAL)
	var method: String = str(RenderingServer.get_current_rendering_method())
	var profile: Dictionary = settings(_quality, method)
	var count: int = int(profile["count"])
	if count <= 0:
		# Downgrading graphics should release the captured GPU cubemaps.
		_release_all()
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		_hide_all()
		return
	var eye := Vector2(camera.global_position.x, camera.global_position.z)
	var candidates: Array = []
	var radius: float = float(profile["radius"])
	for node in get_tree().get_nodes_in_group(GROUP):
		if not (node is Node3D) or not node.is_inside_tree():
			continue
		var anchor := node as Node3D
		var point := Vector2(anchor.global_position.x, anchor.global_position.z)
		var d2: float = eye.distance_squared_to(point)
		if d2 <= (radius + SWITCH_HYSTERESIS) * (radius + SWITCH_HYSTERESIS):
			candidates.append({"node": anchor, "id": anchor.get_instance_id(),
				"distance_sq": d2})
	var selected: Array = choose(candidates, count, radius, _assigned)
	var lighting := Vector2(-1.0, -1.0)
	if is_instance_valid(atmosphere):
		lighting = weather_signature(
			float(atmosphere.get("light_level")), float(atmosphere.get("storm")))
	for i in _probes.size():
		if i >= selected.size() or i >= count:
			_probes[i].visible = false
			_assigned[i] = -1
	for i in selected.size():
		var item: Dictionary = selected[i]
		var id: int = int(item["id"])
		if i < _probes.size() and _assigned[i] == id:
			_probes[i].visible = true
			# Godot UPDATE_ONCE never re-renders a stationary cubemap.
			# A changed storm or sunset needs a native *on-demand* request.
			# One refresh maximum across the global pool each 18 seconds.
			if _weather_refresh_elapsed >= WEATHER_RECAPTURE_INTERVAL \
					and _capture_elapsed >= CAPTURE_COOLDOWN \
					and i < _weather_at_capture.size() \
					and weather_changed(_weather_at_capture[i], lighting) \
					and _probes[i].has_method("request_update"):
				_probes[i].call("request_update")
				_weather_at_capture[i] = lighting
				_weather_refresh_elapsed = 0.0
				_capture_elapsed = 0.0
			continue
		if _capture_elapsed < CAPTURE_COOLDOWN:
			if i < _probes.size():
				_probes[i].visible = false
			continue
		if i >= _probes.size():
			var new_probe: ReflectionProbe = make_probe(profile)
			add_child(new_probe)
			_probes.append(new_probe)
			_assigned.append(-1)
			_weather_at_capture.append(Vector2(-1.0, -1.0))
		var active: ReflectionProbe = _probes[i]
		active.visible = false
		active.mesh_lod_threshold = float(profile["mesh_lod"])
		active.max_distance = float(profile["max_distance"])
		active.global_position = (item["node"] as Node3D).global_position
		active.visible = true
		_assigned[i] = id
		_weather_at_capture[i] = lighting
		_capture_elapsed = 0.0
		_weather_refresh_elapsed = 0.0


func _hide_all() -> void:
	for i in _probes.size():
		_probes[i].visible = false
		_assigned[i] = -1


func _release_all() -> void:
	for probe in _probes:
		probe.queue_free()
	_probes.clear()
	_assigned.clear()
	_weather_at_capture.clear()
	_weather_refresh_elapsed = WEATHER_RECAPTURE_INTERVAL
