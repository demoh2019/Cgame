extends RefCounted
## One native call for a color ramp's packed sample positions. The scalar path
## keeps the client compatible with stock Godot and standalone test runners.


static func make_gradient(first: Color, last: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_colors(PackedColorArray([first, last]))
	return gradient


static func sample_many(gradient: Gradient, offsets: PackedFloat32Array,
		force_scalar: bool = false) -> PackedColorArray:
	if gradient == null:
		return PackedColorArray()
	if not force_scalar and gradient.has_method("sample_batch"):
		var native_colors: PackedColorArray = gradient.call("sample_batch", offsets)
		if native_colors.size() == offsets.size():
			return native_colors
	var colors := PackedColorArray()
	colors.resize(offsets.size())
	for i in offsets.size():
		colors[i] = gradient.sample(offsets[i])
	return colors
