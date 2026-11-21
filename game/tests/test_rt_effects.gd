extends RefCounted
## Hardware ray-traced shadows / AO: feature gating, BLAS input extraction,
## budget logic, parameter packing and shader source presence. No GPU needed
## (headless has no rendering device, which is exactly the fallback path).

const RtEffects = preload("res://scripts/client/rt_effects.gd")
const RtEffect = preload("res://scripts/client/rt_compositor_effect.gd")


func _surface_mesh(indexed: bool, primitive: Mesh.PrimitiveType = Mesh.PRIMITIVE_TRIANGLES) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)])
	if indexed:
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(primitive, arrays)
	return m


func run(t) -> void:
	t.current = "feature detection fallback"
	t.check(not RtEffects.is_supported(null), "no device means no ray tracing")
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	t.check(not RtEffects.is_supported(rd) or rd.has_feature(RenderingDevice.SUPPORTS_RAY_QUERY), "support implies the ray query feature")
	var node: Node = RtEffects.new()
	var cam := Camera3D.new()
	var root := Node3D.new()
	if rd == null:
		t.check(not node.attach(cam, root, null), "attach is a silent no-op without a device")
		t.check(not node.is_active(), "inactive without a device")
	var compat: Node = RtEffects.new()
	t.check(not compat.attach(cam, root, null, "gl_compatibility"), "compatibility renderer never attaches")
	compat.free()
	node.free()
	cam.free()
	root.free()

	t.current = "quality settings"
	t.check(not bool(RtEffects.settings(0)["enabled"]), "tier 0 is off")
	t.check(not bool(RtEffects.settings(2, "mobile")["enabled"]), "only forward+ is supported")
	t.check(bool(RtEffects.settings(1)["shadows"]) and not bool(RtEffects.settings(1)["ao"]), "tier 1 is shadows only")
	t.check(bool(RtEffects.settings(2)["ao"]), "tier 2 adds AO")
	t.check(int(RtEffects.settings(3)["ao_rays"]) > int(RtEffects.settings(2)["ao_rays"]), "tier 3 casts more AO rays")
	t.check(int(RtEffects.settings(99)["max_instances"]) == int(RtEffects.settings(3)["max_instances"]), "levels are clamped")

	t.current = "blas input extraction"
	var indexed: Dictionary = RtEffects.extract_triangles(_surface_mesh(true), 0)
	t.check(bool(indexed["ok"]), "indexed quad extracts")
	var idx: PackedInt32Array = indexed["indices"]
	t.eq(idx.size(), 6, "quad has six indices")
	var plain: Dictionary = RtEffects.extract_triangles(_surface_mesh(false), 0)
	var plain_idx: PackedInt32Array = plain["indices"]
	t.check(not bool(plain["ok"]), "4 vertices without indices is not a multiple of 3")
	t.eq(plain_idx.size(), 0, "rejected surface has no indices")
	var box_result: Dictionary = RtEffects.extract_triangles(BoxMesh.new(), 0)
	var box_v: PackedVector3Array = box_result["vertices"]
	var box_i: PackedInt32Array = box_result["indices"]
	t.check(bool(box_result["ok"]), "box mesh extracts")
	t.eq(box_i.size(), 36, "box has 12 triangles")
	t.check(box_v.size() >= 8, "box has vertices")
	t.check(not bool(RtEffects.extract_triangles(_surface_mesh(true, Mesh.PRIMITIVE_LINES), 0)["ok"]), "non-triangle surfaces are skipped")
	t.check(not bool(RtEffects.extract_triangles(null, 0)["ok"]), "null mesh is rejected")
	t.check(not bool(RtEffects.extract_triangles(BoxMesh.new(), 3)["ok"]), "out-of-range surface is rejected")
	t.eq(RtEffects.pack_positions(box_v).size(), box_v.size() * 12, "positions are tightly packed R32G32B32")
	t.eq(RtEffects.pack_indices(box_i).size(), box_i.size() * 4, "indices are 32-bit")
	var packed: PackedByteArray = RtEffects.pack_positions(PackedVector3Array([Vector3(1, 2, 3)]))
	t.near(packed.decode_float(4), 2.0, 0.0001, "y lands at byte 4")
	var mesh_a: Mesh = BoxMesh.new()
	var mesh_b: Mesh = BoxMesh.new()
	t.check(RtEffects.blas_key(mesh_a, 0) != RtEffects.blas_key(mesh_b, 0), "distinct meshes get distinct keys")
	t.check(RtEffects.blas_key(mesh_a, 0) != RtEffects.blas_key(mesh_a, 1), "surfaces of one mesh get distinct keys")

	t.current = "instance budget"
	var cands: Array[Dictionary] = []
	for d in [30.0, 5.0, 12.0, 90.0, 12.0]:
		cands.append({"position": Vector3(d, 0, 0), "radius": 0.0, "tag": d})
	var picked: Array[Dictionary] = RtEffects.select_nearest(cands, Vector3.ZERO, 50.0, 3)
	t.eq(picked.size(), 3, "capped at max count")
	t.eq(float(picked[0]["tag"]), 5.0, "nearest first")
	t.eq(float(picked[1]["tag"]), 12.0, "then next nearest")
	t.eq(RtEffects.select_nearest(cands, Vector3.ZERO, 50.0, 10).size(), 4, "beyond max distance is dropped")
	var big: Array[Dictionary] = [{"position": Vector3(60, 0, 0), "radius": 20.0}]
	t.eq(RtEffects.select_nearest(big, Vector3.ZERO, 50.0, 5).size(), 1, "radius extends reach")
	t.eq(RtEffects.budget_take(10, 2), 2, "per-frame budget caps work")
	t.eq(RtEffects.budget_take(1, 4), 1, "fewer pending than budget")
	t.eq(RtEffects.budget_take(5, -3), 0, "negative budget is zero")
	t.eq(RtEffect.builds_this_frame(7, 3), 3, "BLAS build budget")
	t.eq(RtEffect.builds_this_frame(0, 3), 0, "nothing queued")

	t.current = "blas eviction"
	var used: Dictionary = {1: 10, 2: 500, 3: 20, 4: 400}
	t.eq(RtEffect.eviction_candidates(used, 600, 4, 10).size(), 0, "under the cap nothing is evicted")
	var victims: Array = RtEffect.eviction_candidates(used, 600, 4, 2)
	t.eq(victims.size(), 2, "evict down to the cap")
	t.eq(victims[0], 1, "oldest first")
	t.eq(RtEffect.eviction_candidates(used, 100, 4, 1).size(), 0, "recently used entries are kept")

	t.current = "params packing"
	t.eq(RtEffect.group_count(1920), 240, "exact multiple")
	t.eq(RtEffect.group_count(1921), 241, "rounds up")
	var cfg: Dictionary = RtEffects.settings(2)
	var bytes: PackedByteArray = RtEffect.pack_params(Projection.IDENTITY, Transform3D.IDENTITY, Projection.IDENTITY,
			Vector3(0, 1, 0), 0.01, Vector2i(640, 360), 7, 2, cfg)
	t.eq(bytes.size(), RtEffect.PARAMS_SIZE, "std140 block size")
	t.near(bytes.decode_float(0), 1.0, 0.0001, "inv_proj diagonal")
	t.near(bytes.decode_float(196), 1.0, 0.0001, "sun y at byte 196")
	t.near(bytes.decode_float(208), 640.0, 0.0001, "width")
	t.near(bytes.decode_float(220), 2.0, 0.0001, "ao rays")
	t.near(bytes.decode_float(240), 1.0, 0.0001, "shadow strength")
	var shadows_off: Dictionary = cfg.duplicate()
	shadows_off["shadows"] = false
	var off_bytes: PackedByteArray = RtEffect.pack_params(Projection.IDENTITY, Transform3D.IDENTITY, Projection.IDENTITY,
			Vector3.UP, 0.01, Vector2i(8, 8), 1, 1, shadows_off)
	t.near(off_bytes.decode_float(240), 0.0, 0.0001, "disabled shadows zero their strength")

	t.current = "shader sources"
	for pass_name in ["rt_shadows", "rt_ao", "rt_denoise"]:
		var path: String = RtEffect.shader_path(pass_name)
		t.check(FileAccess.file_exists(path), "%s exists" % path)
		var text: String = FileAccess.get_file_as_string(path)
		t.check(text.begins_with("#[compute]"), "%s has the compute header" % pass_name)
		t.check(text.contains(RtEffect.COMMON_INCLUDE), "%s includes the common block" % pass_name)
	var shadows_src: String = FileAccess.get_file_as_string(RtEffect.shader_path("rt_shadows"))
	var ao_src: String = FileAccess.get_file_as_string(RtEffect.shader_path("rt_ao"))
	var common: String = FileAccess.get_file_as_string("res://shaders/compute/rt_common.inc")
	t.check(shadows_src.contains("GL_EXT_ray_query") and ao_src.contains("GL_EXT_ray_query"), "ray query extension required")
	t.check(common.contains("rayQueryInitializeEXT") and common.contains("rayQueryProceedEXT"), "ray query traversal present")
	t.check(shadows_src.contains("accelerationStructureEXT") and ao_src.contains("accelerationStructureEXT"), "TLAS uniform bound")
	var merged: String = RtEffect.prepare_source(shadows_src, common)
	t.check(not merged.contains("#[compute]") and not merged.contains(RtEffect.COMMON_INCLUDE), "prepared source is self-contained")
	t.check(merged.contains("RtParams"), "common block is inlined")

	t.current = "effect object"
	var effect: CompositorEffect = RtEffect.new()
	t.eq(effect.effect_callback_type, CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE, "runs after opaque geometry")
	t.check(not effect.is_active(), "starts inactive")
	effect.submit([], {1: {"vertices": PackedByteArray(), "indices": PackedByteArray(), "vertex_count": 0, "index_count": 0}}, Vector3.UP, 0.01)
	t.eq(effect.take_evicted_keys().size(), 0, "no evictions yet")
	t.check(not RtEffects.is_supported(null), "effect creation does not need a device")
