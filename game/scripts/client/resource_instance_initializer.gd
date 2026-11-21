extends RefCounted
## Initialize world-resource MultiMesh instances without individual script
## calls when native sparse batch APIs are available. The server owns IDs.
## Small groups use the legacy path because sorting/batch allocations can
## cost more than a handful of direct instance calls.
const MIN_NATIVE_BATCH := 12

static func _finite_color(value: Color) -> bool:
	return not (is_nan(value.r) or is_inf(value.r)
		or is_nan(value.g) or is_inf(value.g)
		or is_nan(value.b) or is_inf(value.b)
		or is_nan(value.a) or is_inf(value.a))

## The caller keeps the original transforms and resource-ID mapping.
## No renderer updates are sent until every transform and color is valid.
static func initialize(mm: MultiMesh, transforms: Array,
		colors: PackedColorArray) -> bool:
	if mm == null or mm.transform_format != MultiMesh.TRANSFORM_3D:
		return false
	if not mm.use_colors or transforms.size() != colors.size():
		return false
	if transforms.size() != mm.instance_count:
		return false
	for i in transforms.size():
		if not (transforms[i] is Transform3D):
			return false
		var transform: Transform3D = transforms[i]
		if not transform.is_finite() or not _finite_color(colors[i]):
			return false

	var count: int = transforms.size()
	var native_transforms: bool = count >= MIN_NATIVE_BATCH and mm.has_method("set_instance_transforms_batch")
	var native_colors: bool = count >= MIN_NATIVE_BATCH and mm.has_method("set_instance_colors_batch")
	var indices := PackedInt32Array()
	if native_transforms or native_colors:
		indices.resize(count)
		for i in count:
			indices[i] = i

	var transformed := false
	if native_transforms:
		var typed: Array[Transform3D] = []
		for transform in transforms:
			var typed_transform: Transform3D = transform
			typed.append(typed_transform)
		transformed = bool(mm.call("set_instance_transforms_batch", indices, typed))
	if not transformed:
		for i in count:
			mm.set_instance_transform(i, transforms[i])

	var tinted := false
	if native_colors:
		tinted = bool(mm.call("set_instance_colors_batch", indices, colors))
	if not tinted:
		for i in count:
			mm.set_instance_color(i, colors[i])
	return true
