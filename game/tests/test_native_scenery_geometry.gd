extends RefCounted
## Native Cgame / stock Godot scenery packing and bounds parity.
const Batches = preload("res://scripts/client/scenery_batches.gd")


func run(t) -> void:
	t.current = "static scene GPU records and world-stable plant pigments"
	var transforms: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(1.25, 3.0, 4.5)),
		Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3(1.4, 0.9, 1.1)), Vector3(-3.25, 7.5, 2.25)),
		Transform3D(Basis(Vector3.RIGHT, 0.35).scaled(Vector3(1.2, 1.7, 0.7)), Vector3(9.0, -2.0, -6.0)),
	]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 3.0, 1.5)
	var origin := Vector2(224.0, -640.0)
	for tinted in [false, true]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = tinted
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		var reference: PackedFloat32Array = Batches.packed_group(transforms, tinted, origin)
		var candidate: PackedFloat32Array = Batches.packed_group_for(mm, transforms, tinted, origin)
		t.eq(candidate, reference,
			"native row-major transforms and plant tint match original GDScript packed data")
		mm.buffer = candidate
		t.eq(mm.instance_count, transforms.size(),
			"native upload does not change object count")
		for i in transforms.size():
			t.check(mm.get_instance_transform(i).is_equal_approx(transforms[i]),
				"native GPU-packed model remains at the exact authored position, scale and rotation")
			if tinted:
				var c: Color = Batches.tint_at(origin + Vector2(transforms[i].origin.x, transforms[i].origin.z))
				var uploaded: Color = mm.get_instance_color(i)
				t.check(uploaded.is_equal_approx(c),
					"native buffer preserves per-flower tint with no shader change")
		var reference_box: AABB = Batches.bounds_for(mesh, transforms)
		var native_box: AABB = Batches.bounds_for_instance(mm, mesh, transforms)
		t.check(native_box.is_equal_approx(reference_box),
			"native visible AABB matches union of all transformed model extents")
		for tr in transforms:
			t.check(native_box.has_point(tr.origin),
				"bounds include every tree, rotated rock and wildflower centre")

	t.current = "live chunk batching remains GPU instanced and cullable"
	var root := Node3D.new()
	var batches: Array[MultiMeshInstance3D] = Batches.add(root, mesh, transforms, 84.0, false,
		8.0, true, origin)
	t.eq(batches.size(), 1, "sparse decoration remains one GPU draw call")
	if not batches.is_empty():
		t.eq(batches[0].multimesh.instance_count, transforms.size(),
			"live scenery keeps all instances in the original order")
		t.check(batches[0].custom_aabb.has_point(transforms[0].origin),
			"real MultiMesh draw bounds include populated world area")
		t.near(batches[0].visibility_range_end, 84.0, 0.001,
			"quality and distance LOD behavior remains unchanged")
	root.free()

	t.current = "native fast path is optional, stock Godot remains functional"
	var source: String = (Batches as Script).source_code
	t.check(source.contains('multimesh.has_method("pack_transform_buffer")'),
		"canonical game uses engine buffer packing when present")
	t.check(source.contains('multimesh.has_method("transformed_mesh_bounds")'),
		"canonical game uses native batch bounds when present")
	t.check(source.contains('return packed_group(transforms, tinted, world_origin)'),
		"stock Godot still builds exactly the same GPU instance buffer")
	t.check(source.contains("return bounds_for(mesh, transforms)"),
		"stock Godot still maintains safe per-mesh visibility bounds")
