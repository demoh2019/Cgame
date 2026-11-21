extends RefCounted
## Renderer buffer layout/atomicity tests for canonical Albion After resources.
const Initializer = preload("res://scripts/client/resource_instance_initializer.gd")

func run(t) -> void:
	t.current = "dense resource colors and nontrivial transforms share full buffer"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 12
	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	for i in 12:
		var basis := Basis(Vector3.UP, PI * 0.5) if i == 3 else Basis.IDENTITY
		transforms.append(Transform3D(basis.scaled(Vector3(2, 3, 4)),
			Vector3(float(i), 10.0, -5.0)))
		colors.append(Color(0.25, 0.5, 0.75, 1) if i % 2 == 0 else Color(1, 0, 0, 1))
	t.check(Initializer.initialize(mm, transforms, colors), "dense group initializes")
	var buffer: PackedFloat32Array = mm.buffer
	t.eq(buffer.size(), 12 * 16, "exact full 3D+RGBA stride")
	t.eq(mm.instance_count, 12, "no allocation or removal")
	t.eq(mm.visible_instance_count, -1, "visible range unchanged")
	for i in 12:
		t.check(mm.get_instance_transform(i).is_equal_approx(transforms[i]), "instance transform preserved after 32-bit GPU packing")
		t.eq(mm.get_instance_color(i), colors[i], "instance color preserved from packed data")
	# The renderer buffer is row-major, not the column-major Basis view.
	t.near(buffer[3 * 16 + 3], 3.0, 0.00001, "rotation-safe transform X origin")
	t.near(buffer[3 * 16 + 7], 10.0, 0.00001, "rotation-safe transform Y origin")
	t.near(buffer[3 * 16 + 11], -5.0, 0.00001, "rotation-safe transform Z origin")
	t.near(buffer[3 * 16 + 12], colors[3].r, 0.00001, "red channel at stride 12")
	t.near(buffer[3 * 16 + 15], colors[3].a, 0.00001, "alpha channel at stride 15")

	t.current = "failed full initialization does not partially overwrite GPU buffer"
	var original_buffer: PackedFloat32Array = mm.buffer
	var wrong_colors := colors.duplicate()
	wrong_colors.remove_at(0)
	t.check(not Initializer.initialize(mm, transforms, wrong_colors), "wrong array length rejected")
	t.eq(mm.buffer, original_buffer, "buffer unchanged after length mismatch")
	var wrong_transforms: Array = []
	for transform in transforms:
		wrong_transforms.append(transform)
	wrong_transforms[8] = Vector3.ZERO
	t.check(not Initializer.initialize(mm, wrong_transforms, colors), "wrong transform variant rejected")
	t.eq(mm.buffer, original_buffer, "buffer unchanged after wrong transform type")
	var wrong_float := colors.duplicate()
	wrong_float[11] = Color(INF, 0, 0, 1)
	t.check(not Initializer.initialize(mm, transforms, wrong_float), "nonfinite color rejected")
	t.eq(mm.buffer, original_buffer, "buffer unchanged after nonfinite color")

	t.current = "special instance formats do not discard shader custom data"
	var custom := MultiMesh.new()
	custom.transform_format = MultiMesh.TRANSFORM_3D
	custom.use_colors = true
	custom.use_custom_data = true
	custom.mesh = BoxMesh.new()
	custom.instance_count = 12
	custom.set_instance_custom_data(5, Color(0.25, 0.5, 0.75, 1))
	t.check(Initializer.initialize(custom, transforms, colors), "custom format uses compatible per-slot path")
	t.eq(custom.get_instance_custom_data(5), Color(0.25, 0.5, 0.75, 1),
		"existing shader custom data is not overwritten")
	t.eq(custom.get_instance_transform(3), transforms[3], "custom format preserves transforms")

	t.current = "zero and small groups retain prior compatibility"
	var empty := MultiMesh.new()
	empty.use_colors = true
	empty.instance_count = 0
	t.check(Initializer.initialize(empty, [], PackedColorArray()), "empty buffer accepted")
	var small := MultiMesh.new()
	small.use_colors = true
	small.instance_count = 1
	var one: Array = [Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))]
	t.check(Initializer.initialize(small, one, PackedColorArray([Color.WHITE])),
		"small group uses legacy setter")
	t.eq(small.get_instance_transform(0).origin, Vector3(1, 2, 3),
		"small group transform unchanged")
