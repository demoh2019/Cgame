extends RefCounted
## Deterministic screen-space LOD / frustum-culling clusters for dense static world instances.
## Partition only repeated scenery. Server ids and transforms remain untouched.

const MIN_INSTANCES := 12
const SUBCELLS := 2


static func supports_partition(kind: String) -> bool:
	# Never split loot crates, ruins, walls or other gameplay-critical landmarks.
	return kind.begins_with("tree:") or kind.begins_with("rock:") or kind.begins_with("ore:")


static func key_for(kind: String, world_position: Vector2, origin: Vector2, chunk_size: float,
		subcells: int = SUBCELLS) -> String:
	var side: int = maxi(subcells, 1)
	var size: float = maxf(chunk_size, 0.01)
	var local: Vector2 = (world_position - origin) / size
	var x: int = clampi(floori(local.x * float(side)), 0, side - 1)
	var y: int = clampi(floori(local.y * float(side)), 0, side - 1)
	return "%s|%d|%d" % [kind, x, y]


## Output: stable batch id -> {kind, nodes}; the resource id on every node is preserved.
static func partition(by_kind: Dictionary, origin: Vector2, chunk_size: float,
		min_instances: int = MIN_INSTANCES, subcells: int = SUBCELLS) -> Dictionary:
	var batches: Dictionary = {}
	for kind_variant in by_kind:
		var kind: String = str(kind_variant)
		var nodes: Array = by_kind[kind_variant]
		if not supports_partition(kind) or nodes.size() < min_instances or subcells < 2:
			batches[kind] = {"kind": kind, "nodes": nodes}
			continue
		# The cell lookup uses an integer key while building; format the stable
		# string batch id only once per occupied cell, not once per instance.
		var side: int = maxi(subcells, 1)
		var size: float = maxf(chunk_size, 0.01)
		var local_buckets: Dictionary = {}
		for node in nodes:
			var world_position := Vector2(float(node["x"]), float(node["z"]))
			var local: Vector2 = (world_position - origin) / size
			var cell := Vector2i(
				clampi(floori(local.x * float(side)), 0, side - 1),
				clampi(floori(local.y * float(side)), 0, side - 1))
			var members: Array = local_buckets.get(cell) as Array
			if members == null:
				members = []
				local_buckets[cell] = members
				var batch_id: String = "%s|%d|%d" % [kind, cell.x, cell.y]
				batches[batch_id] = {"kind": kind, "nodes": members}
			members.append(node)
	return batches
