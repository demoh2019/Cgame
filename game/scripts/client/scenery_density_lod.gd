extends RefCounted
## Unreal foliage.DensityScale-style runtime geometry density for CLIENT
## decoration MultiMeshes only. Native engine batches counts at once.
## Existing MultiMesh buffers are immutable after creation: visible_instance_count
## is the only GPU-facing property updated when quality/distance changes.

const MAX_INSTANCES := 65536
const MAX_CLUSTERS := 4096
const MAX_DISTANCE := 10000000.0
const NEAR_DISTANCE := 18.0
const FAR_DISTANCE := 125.0
const NEAR_DENSITY := [0.42, 0.68, 0.88, 1.0]
const FAR_DENSITY := [0.20, 0.42, 0.70, 1.0]

static var _native_checked := false
static var _native: Object = null


static func _engine() -> Object:
	if not _native_checked:
		_native_checked = true
		if ClassDB.class_exists("PCGFoliageScalability3D"):
			var instance: Object = ClassDB.instantiate("PCGFoliageScalability3D")
			if instance != null and instance.has_method("spread_indices") and \
					instance.has_method("plan_visible_counts"):
				_native = instance
	return _native


## A reversible bit-reversed order ensures that drawing a prefix of a cluster
## does not display only the first anchors in its deterministic spawn sequence.
static func spread_indices(count: int, prefer_native: bool = true) -> PackedInt32Array:
	if prefer_native:
		var native: Object = _engine()
		if native != null:
			return native.call("spread_indices", count)
	var result := PackedInt32Array()
	if count < 0 or count > MAX_INSTANCES:
		return result
	var bits := 0
	var padded := 1
	while padded < count:
		padded <<= 1
		bits += 1
	for slot in padded:
		var source := 0
		for bit in bits:
			source = (source << 1) | ((slot >> bit) & 1)
		if source < count:
			result.append(source)
	return result


static func distribute_transforms(transforms: Array[Transform3D],
		prefer_native: bool = true) -> Array[Transform3D]:
	var order: PackedInt32Array = spread_indices(transforms.size(), prefer_native)
	if order.size() != transforms.size():
		return transforms.duplicate()
	var result: Array[Transform3D] = []
	for index in order:
		result.append(transforms[index])
	return result


static func _plan_fallback(counts: PackedInt32Array,
		distances: PackedFloat32Array, quality: int,
		near_distance: float, far_distance: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	if counts.size() != distances.size() or counts.size() > MAX_CLUSTERS or \
			quality < 0 or quality > 3 or not is_finite(near_distance) or \
			not is_finite(far_distance) or near_distance < 0.0 or \
			near_distance >= far_distance or far_distance > 1000000.0:
		return result
	for i in counts.size():
		if counts[i] < 0 or counts[i] > MAX_INSTANCES or \
				not is_finite(distances[i]) or distances[i] < 0.0 or \
				distances[i] > MAX_DISTANCE:
			return PackedInt32Array()
	for i in counts.size():
		var count: int = counts[i]
		if count == 0 or quality == 3:
			result.append(count)
			continue
		var progress: float = clampf(
			(float(distances[i]) - near_distance) / (far_distance - near_distance),
			0.0, 1.0)
		var fade: float = progress * progress * (3.0 - 2.0 * progress)
		var density: float = float(NEAR_DENSITY[quality]) + \
			(float(FAR_DENSITY[quality]) - float(NEAR_DENSITY[quality])) * fade
		result.append(clampi(roundi(float(count) * density), 1, count))
	return result


static func plan_visible_counts(counts: PackedInt32Array,
		distances: PackedFloat32Array, quality: int,
		near_distance: float = NEAR_DISTANCE,
		far_distance: float = FAR_DISTANCE,
		prefer_native: bool = true) -> PackedInt32Array:
	if prefer_native:
		var native: Object = _engine()
		if native != null:
			return native.call("plan_visible_counts", counts, distances,
				quality, near_distance, far_distance)
	return _plan_fallback(counts, distances, quality, near_distance, far_distance)


## Time-coherent Unreal foliage density planning: a tiny count deadband
## prevents one/two plants popping on each 0.6-second camera update. A -1
## previous value explicitly bypasses hysteresis after quality changes.
const DENSITY_DEADBAND := 2
const LAST_QUALITY_META := "aa_density_lod_quality"


static func _stable_fallback(counts: PackedInt32Array, distances: PackedFloat32Array,
		previous_counts: PackedInt32Array, quality: int, deadband: int,
		near_distance: float, far_distance: float) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if counts.size() != previous_counts.size() or counts.size() > MAX_CLUSTERS or \
			deadband < 0 or deadband > 8:
		return empty
	for i in counts.size():
		if previous_counts[i] < -1 or previous_counts[i] > counts[i]:
			return empty
	var selected: PackedInt32Array = _plan_fallback(
		counts, distances, quality, near_distance, far_distance)
	if selected.size() != counts.size():
		return empty
	for i in counts.size():
		var previous: int = previous_counts[i]
		var desired: int = selected[i]
		if previous >= 0 and (counts[i] == 0 or previous > 0) and \
				absi(previous - desired) <= deadband:
			selected[i] = previous
	return selected


static func plan_visible_counts_stable(counts: PackedInt32Array,
		distances: PackedFloat32Array, previous_counts: PackedInt32Array,
		quality: int, deadband: int = DENSITY_DEADBAND,
		near_distance: float = NEAR_DISTANCE, far_distance: float = FAR_DISTANCE,
		prefer_native: bool = true) -> PackedInt32Array:
	if prefer_native:
		var native: Object = _engine()
		# Stock Godot and older Cgame binaries retain the exact same policy.
		if native != null and native.has_method("plan_visible_counts_stable"):
			return native.call("plan_visible_counts_stable",
				counts, distances, previous_counts, quality, deadband,
				near_distance, far_distance)
	return _stable_fallback(counts, distances, previous_counts,
		quality, deadband, near_distance, far_distance)


## Call once per chunk at a slow refresh cadence. Static authored mesh
## visibility ranges/frustum culling still operate independently.
static func update_instances(instances: Array[MultiMeshInstance3D],
		camera_position: Vector3, quality: int, prefer_native: bool = true) -> void:
	if instances.is_empty() or not camera_position.is_finite():
		return
	var valid: Array[MultiMeshInstance3D] = []
	var counts := PackedInt32Array()
	var distances := PackedFloat32Array()
	for node in instances:
		if node == null or not is_instance_valid(node) or node.multimesh == null or \
				not node.is_inside_tree() or not bool(node.get_meta("aa_density_scalable", false)):
			continue
		var center: Vector3 = node.to_global(node.custom_aabb.get_center())
		if not center.is_finite():
			continue
		valid.append(node)
		counts.append(node.multimesh.instance_count)
		distances.append(center.distance_to(camera_position))
		if valid.size() == MAX_CLUSTERS:
			_apply_plan(valid, counts, distances, quality, prefer_native)
			valid.clear()
			counts.clear()
			distances.clear()
	_apply_plan(valid, counts, distances, quality, prefer_native)


static func _apply_plan(instances: Array[MultiMeshInstance3D],
		counts: PackedInt32Array, distances: PackedFloat32Array,
		quality: int, prefer_native: bool) -> void:
	if instances.is_empty():
		return
	# History belongs to the visual MultiMesh node, not the engine or the
	# authoritative world. Quality tier switches force immediate recovery.
	var previous := PackedInt32Array()
	for i in instances.size():
		var node: MultiMeshInstance3D = instances[i]
		var old_visible: int = node.multimesh.visible_instance_count
		var same_quality: bool = int(node.get_meta(LAST_QUALITY_META, -1)) == quality
		previous.append(old_visible if same_quality and old_visible >= 0 and
			old_visible <= counts[i] else -1)
	var selected: PackedInt32Array = plan_visible_counts_stable(
		counts, distances, previous, quality, DENSITY_DEADBAND,
		NEAR_DISTANCE, FAR_DISTANCE, prefer_native)
	# Never apply partial results from a malformed native batch.
	if selected.size() != instances.size():
		selected = _stable_fallback(counts, distances, previous, quality,
			DENSITY_DEADBAND, NEAR_DISTANCE, FAR_DISTANCE)
	if selected.size() != instances.size():
		return
	for i in instances.size():
		var node: MultiMeshInstance3D = instances[i]
		var current: MultiMesh = node.multimesh
		var visible: int = selected[i]
		if current != null:
			if current.visible_instance_count != visible:
				current.visible_instance_count = visible
			node.set_meta(LAST_QUALITY_META, quality)
