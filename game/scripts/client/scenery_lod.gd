extends RefCounted
## GPU geometry budgets for the world's already-batched MultiMeshes.
## GeometryInstance3D LOD bias uses imported mesh LODs where available.
## Visibility ranges cheaply cull far, non-critical decorations as a batch.
## Game objects and their collision/loot server state are never removed.

const PRESETS := [
	{"tree": 112.0, "rock": 94.0, "bush": 66.0, "prop": 72.0,
		"decor_scale": 0.55, "lod_bias": 0.70},
	{"tree": 160.0, "rock": 136.0, "bush": 104.0, "prop": 118.0,
		"decor_scale": 0.80, "lod_bias": 1.0},
	{"tree": 205.0, "rock": 184.0, "bush": 145.0, "prop": 160.0,
		"decor_scale": 1.0, "lod_bias": 1.20},
	{"tree": 260.0, "rock": 224.0, "bush": 185.0, "prop": 205.0,
		"decor_scale": 1.2, "lod_bias": 1.50},
]


static func preset(quality: int) -> Dictionary:
	return PRESETS[clampi(quality, 0, PRESETS.size() - 1)].duplicate(true)


## Dither distance, only for high-fidelity foliage; low tiers keep zero
## extra fragment work. Culling remains the existing MultiMesh end range.
static func foliage_fade_width(quality: int) -> float:
	return [0.0, 0.0, 14.0, 22.0][clampi(quality, 0, 3)]


static func category(kind: String) -> String:
	if kind.begins_with("tree:") or kind == "tree":
		return "tree"
	if kind.begins_with("rock:") or kind == "rock" or kind.begins_with("ore:") or kind == "ore":
		return "rock"
	if kind == "bush" or kind == "berry":
		return "bush"
	if kind.begins_with("prop:") or kind.begins_with("crate"):
		return "prop"
	if kind.begins_with("decor:"):
		return "decor"
	return "landmark"


static func range_for(kind: String, quality: int, base_distance: float = 0.0) -> float:
	var limits: Dictionary = preset(quality)
	if base_distance > 0.0:
		return maxf(24.0, base_distance * float(limits["decor_scale"]))
	var group: String = category(kind)
	# Settlements, defensive walls, monuments and workshops remain visible
	# for navigation no matter which user-facing graphics level is selected.
	if not limits.has(group):
		return 0.0
	return float(limits[group])


## Unreal Cull Distance Volume-inspired pure size-pair resolution.
## The native engine resolves nearest longest-side size, unsorted pairs, and
## a designer-authored max draw distance. Stock Godot uses the same policy.
static var _cull_native: Object = null
static var _cull_checked := false


static func _cull_range_fallback(bounds: AABB,
		sizes: PackedFloat32Array, ranges: PackedFloat32Array,
		authored_distance: float) -> float:
	if sizes.is_empty() or sizes.size() != ranges.size() or sizes.size() > 128 or \
			not is_finite(authored_distance) or authored_distance < 0.0 or \
			authored_distance > 1000000.0 or \
			not bounds.position.is_finite() or not bounds.size.is_finite() or \
			absf(bounds.position.x) > 10000000.0 or \
			absf(bounds.position.y) > 10000000.0 or \
			absf(bounds.position.z) > 10000000.0 or \
			bounds.size.x < 0.0 or bounds.size.y < 0.0 or bounds.size.z < 0.0 or \
			bounds.size.x > 1000000.0 or bounds.size.y > 1000000.0 or \
			bounds.size.z > 1000000.0:
		return -1.0
	for i in sizes.size():
		if not is_finite(sizes[i]) or not is_finite(ranges[i]) or \
				sizes[i] < 0.0 or sizes[i] > 1000000.0 or \
				ranges[i] < 0.0 or ranges[i] > 1000000.0:
			return -1.0
	var longest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var nearest := INF
	var selected := 0.0
	for i in sizes.size():
		var difference: float = absf(longest - sizes[i])
		var candidate: float = ranges[i]
		if difference < nearest or (difference == nearest and candidate > 0.0 \
				and (selected == 0.0 or candidate < selected)):
			nearest = difference
			selected = candidate
	if selected == 0.0:
		return authored_distance
	return minf(selected, authored_distance) if authored_distance > 0.0 else selected


## Public game wrapper for both Cgame and stock Godot. -1 from an invalid
## native profile is not applied to the scene.
static func cull_range_for_bounds(bounds: AABB, sizes: PackedFloat32Array,
		ranges: PackedFloat32Array, authored_distance: float,
		prefer_native: bool = true) -> float:
	if prefer_native:
		if not _cull_checked:
			_cull_checked = true
			if ClassDB.class_exists("CullDistanceProfile3D"):
				var instance: Object = ClassDB.instantiate("CullDistanceProfile3D")
				if instance != null and instance.has_method("get_cull_distance"):
					_cull_native = instance
		if _cull_native != null:
			var native_result: float = _cull_native.call(
				"get_cull_distance", bounds, sizes, ranges, authored_distance)
			return native_result
	return _cull_range_fallback(bounds, sizes, ranges, authored_distance)


## Cached profile presets avoid allocating two arrays and revalidating the
## same size-distance pairs for every streamed decorative MultiMesh instance.
## One immutable profile is configured per quality tier. Older custom engines
## and stock Godot use the same cached packed arrays with the legacy method.
static var _decor_profile_sizes: PackedFloat32Array = PackedFloat32Array([1.0, 4.0, 10.0, 24.0, 64.0])
static var _decor_profile_ranges_by_quality: Dictionary = {}
static var _decor_cached_profiles: Dictionary = {}
static var _decor_cached_api_state: int = -1 # -1 unchecked, 0 unavailable, 1 native usable.


static func _decor_ranges_for_quality(level: int) -> PackedFloat32Array:
	var safe_level: int = clampi(level, 0, 3)
	if not _decor_profile_ranges_by_quality.has(safe_level):
		var scale: float = float(PRESETS[safe_level]["decor_scale"])
		_decor_profile_ranges_by_quality[safe_level] = PackedFloat32Array([
			45.0 * scale, 75.0 * scale, 105.0 * scale, 160.0 * scale, 0.0])
	return _decor_profile_ranges_by_quality[safe_level]


static func _decor_native_profile(level: int, sizes: PackedFloat32Array,
		ranges: PackedFloat32Array) -> Object:
	if _decor_cached_api_state == -1:
		_decor_cached_api_state = 0
		if ClassDB.class_exists("CullDistanceProfile3D"):
			var probe: Object = ClassDB.instantiate("CullDistanceProfile3D")
			if probe != null and probe.has_method("configure") and \
					probe.has_method("get_cached_cull_distance"):
				_decor_cached_api_state = 1
				if bool(probe.call("configure", sizes, ranges)):
					_decor_cached_profiles[level] = probe
	if _decor_cached_api_state != 1:
		return null
	if not _decor_cached_profiles.has(level):
		var profile: Object = ClassDB.instantiate("CullDistanceProfile3D")
		if profile == null or not bool(profile.call("configure", sizes, ranges)):
			return null
		_decor_cached_profiles[level] = profile
	return _decor_cached_profiles[level]


## Size-distance pairs are quality-scaled but never override the category or
## the author's draw cap. Large batches remain unchanged (zero cull range).
## Never affects gameplay objects, terrain collisions or landmarks.
static func decor_range_for_bounds(bounds: AABB, quality: int,
		authored_distance: float, prefer_native: bool = true) -> float:
	if authored_distance <= 0.0 or not is_finite(authored_distance) or \
			not bounds.size.is_finite() or bounds.size == Vector3.ZERO:
		return authored_distance
	var safe_level: int = clampi(quality, 0, 3)
	var ranges: PackedFloat32Array = _decor_ranges_for_quality(safe_level)
	if prefer_native:
		var profile: Object = _decor_native_profile(safe_level, _decor_profile_sizes, ranges)
		if profile != null:
			var cached_result: float = float(profile.call(
				"get_cached_cull_distance", bounds, authored_distance))
			return cached_result if cached_result >= 0.0 else authored_distance
	var range_result: float = cull_range_for_bounds(bounds, _decor_profile_sizes,
		ranges, authored_distance, prefer_native)
	return range_result if range_result >= 0.0 else authored_distance


static func apply(instance: MultiMeshInstance3D, kind: String, quality: int,
		base_distance: float = 0.0) -> void:
	if instance == null:
		return
	var limits: Dictionary = preset(quality)
	instance.lod_bias = float(limits["lod_bias"])
	var end_distance: float = range_for(kind, quality, base_distance)
	if category(kind) == "decor" and base_distance > 0.0:
		end_distance = decor_range_for_bounds(instance.custom_aabb, quality, end_distance)
	instance.visibility_range_end = end_distance
	# Hysteresis, not alpha transparency: avoiding a translucent overlap
	# keeps fill rate low and helps reduce popping at LOD thresholds.
	instance.visibility_range_end_margin = 12.0 if instance.visibility_range_end > 0.0 else 0.0


## Change all existing streamed visual batches in one quality update. The
## single-object apply() path still handles newly created chunks and props.
## A native profile resolves up to 4096 decorative AABBs per script-to-C++
## call, instead of issuing one native call per MultiMesh during quality swaps.
const MAX_CULL_BATCH := 4096


static func _apply_decor_cull_batch(instances: Array[MultiMeshInstance3D],
		positions: PackedVector3Array, sizes: PackedVector3Array,
		authored: PackedFloat64Array, quality: int) -> void:
	if instances.is_empty():
		return
	var result := PackedFloat64Array()
	var native: Object = _decor_native_profile(quality,
		_decor_profile_sizes, _decor_ranges_for_quality(quality))
	if native != null and native.has_method("get_cached_cull_distances"):
		result = native.call("get_cached_cull_distances", positions, sizes, authored)
	# An old native engine, invalid response, or stock Godot always takes
	# the exact existing size/cap policy; no partial native results applied.
	var use_native: bool = result.size() == instances.size()
	for i in instances.size():
		var end_distance: float = float(result[i]) if use_native else \
			decor_range_for_bounds(AABB(positions[i], sizes[i]), quality,
				float(authored[i]), false)
		if end_distance < 0.0 or not is_finite(end_distance):
			end_distance = float(authored[i])
		instances[i].visibility_range_end = end_distance
		instances[i].visibility_range_end_margin = 12.0 if end_distance > 0.0 else 0.0


static func apply_many(nodes: Array, quality: int) -> void:
	var safe_quality: int = clampi(quality, 0, 3)
	var limits: Dictionary = PRESETS[safe_quality]
	var pending: Array[MultiMeshInstance3D] = []
	var positions := PackedVector3Array()
	var sizes := PackedVector3Array()
	var authored := PackedFloat64Array()
	for node in nodes:
		if not (node is MultiMeshInstance3D) or not node.has_meta("aa_scenery_kind"):
			continue
		var instance: MultiMeshInstance3D = node
		var kind: String = str(instance.get_meta("aa_scenery_kind"))
		var base_distance: float = float(instance.get_meta("aa_scenery_distance", 0.0))
		var group: String = category(kind)
		var end_distance: float = 0.0
		if base_distance > 0.0:
			end_distance = maxf(24.0, base_distance * float(limits["decor_scale"]))
		elif limits.has(group):
			end_distance = float(limits[group])
		instance.lod_bias = float(limits["lod_bias"])
		instance.visibility_range_end = end_distance
		instance.visibility_range_end_margin = 12.0 if end_distance > 0.0 else 0.0
		if group != "decor" or base_distance <= 0.0 or \
				not is_finite(end_distance) or end_distance <= 0.0:
			continue
		var bounds: AABB = instance.custom_aabb
		# Preserve the previous behavior for unconfigured and invalid AABBs.
		# Invalid entries must not poison an otherwise valid native batch.
		if not bounds.position.is_finite() or not bounds.size.is_finite() or \
				bounds.size == Vector3.ZERO or bounds.size.x < 0.0 or \
				bounds.size.y < 0.0 or bounds.size.z < 0.0 or \
				absf(bounds.position.x) > 10000000.0 or \
				absf(bounds.position.y) > 10000000.0 or \
				absf(bounds.position.z) > 10000000.0 or \
				bounds.size.x > 1000000.0 or bounds.size.y > 1000000.0 or \
				bounds.size.z > 1000000.0 or end_distance > 1000000.0:
			continue
		pending.append(instance)
		positions.append(bounds.position)
		sizes.append(bounds.size)
		authored.append(end_distance)
		if pending.size() == MAX_CULL_BATCH:
			_apply_decor_cull_batch(pending, positions, sizes, authored, safe_quality)
			pending.clear()
			positions.clear()
			sizes.clear()
			authored.clear()
	_apply_decor_cull_batch(pending, positions, sizes, authored, safe_quality)
