extends RefCounted
## Initial placement of server-owned Albion After chunk resources.
## Dense 3D+RGBA groups use ONE full MultiMesh buffer upload instead of
## separate script/renderer updates for every tree, ore and world object.
## For tiny groups or custom shader data, preserve individual legacy setters.
const MIN_NATIVE_BATCH := 12

static func _finite_color(value: Color) -> bool:
	return not (is_nan(value.r) or is_inf(value.r)
		or is_nan(value.g) or is_inf(value.g)
		or is_nan(value.b) or is_inf(value.b)
		or is_nan(value.a) or is_inf(value.a))

## 3D MultiMesh record layout: 12 row-major transform floats, then RGBA.
## Called only with fully validated data. This works on stock Godot.
static func _pack_full_buffer(transforms: Array, colors: PackedColorArray) -> PackedFloat32Array:
	var floats := PackedFloat32Array()
	floats.resize(transforms.size() * 16)
	for i in transforms.size():
		var transform: Transform3D = transforms[i]
		var c: Color = colors[i]
		var o: int = i * 16
		floats[o + 0] = transform.basis.x.x
		floats[o + 1] = transform.basis.y.x
		floats[o + 2] = transform.basis.z.x
		floats[o + 3] = transform.origin.x
		floats[o + 4] = transform.basis.x.y
		floats[o + 5] = transform.basis.y.y
		floats[o + 6] = transform.basis.z.y
		floats[o + 7] = transform.origin.y
		floats[o + 8] = transform.basis.x.z
		floats[o + 9] = transform.basis.y.z
		floats[o + 10] = transform.basis.z.z
		floats[o + 11] = transform.origin.z
		floats[o + 12] = c.r
		floats[o + 13] = c.g
		floats[o + 14] = c.b
		floats[o + 15] = c.a
	return floats

## Never update the renderer until ALL transforms and colors are valid.
## Preserve existing custom instance data when a caller uses that format.
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
	if count >= MIN_NATIVE_BATCH and not mm.use_custom_data:
		if mm.has_method("set_instance_transform_color_buffer"):
			if bool(mm.call("set_instance_transform_color_buffer", transforms, colors)):
				return true
		# Regular Godot uses the very same packed renderer format.
		# Buffer assignment is one full upload, not 2*count setters.
		mm.buffer = _pack_full_buffer(transforms, colors)
		return true

	# Avoid building a large temporary packed buffer for tiny groups.
	# If custom instance data is enabled, do not overwrite that channel.
	for i in count:
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	return true
