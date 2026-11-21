extends RefCounted
## Applies sparse native CGame MultiMesh updates, with a stock Godot fallback.
## Validate all slots and transforms before touching any renderer state.
static func apply(mm: MultiMesh, indices: PackedInt32Array,
		transforms: Array[Transform3D]) -> bool:
	if mm == null or mm.transform_format != MultiMesh.TRANSFORM_3D:
		return false
	if indices.size() != transforms.size():
		return false
	var used: Dictionary = {}
	for n in indices.size():
		var slot: int = indices[n]
		if slot < 0 or slot >= mm.instance_count or used.has(slot):
			return false
		if not transforms[n].is_finite():
			return false
		used[slot] = true
	if mm.has_method("set_instance_transforms_batch"):
		return bool(mm.call("set_instance_transforms_batch", indices, transforms))
	for n in indices.size():
		mm.set_instance_transform(indices[n], transforms[n])
	return true
