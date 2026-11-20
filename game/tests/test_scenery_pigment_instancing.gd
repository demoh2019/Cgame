extends RefCounted
## World-stable plant tinting and one-upload render-only MultiMesh batches.
const Batches = preload("res://scripts/client/scenery_batches.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func run(t) -> void:
	t.current = "plant-only source preservation"
	for kind in ["Fern_1", "Bush_Common", "Bush_Common_Flowers",
			"Plant_1_Big", "Flower_3_Group", "Grass_Wispy_Tall"]:
		t.check(Batches.colorful_plant(kind),
			"decorative undergrowth supports per-instance PBR tint")
	for kind in ["Pebble_Round_1", "Pebble_Square_2",
			"Mushroom_Common", "Petal_1", "Wooden_Crate"]:
		t.check(not Batches.colorful_plant(kind),
			"authored pebble, fungus and discarded petal color remains exact")

	t.current = "world stable deterministic subtle tint"
	var here := Vector2(31.25, -82.75)
	var stable: Color = Batches.tint_at(here)
	t.eq(stable, Batches.tint_at(here), "same world location has same pigment")
	t.near(stable.a, 1.0, 0.000001,
		"pigment does not affect opacity or alpha cutout")
	var varied: Dictionary = {}
	for x in 21:
		var c: Color = Batches.tint_at(here + Vector2(x * 0.41, x * 0.73))
		t.check(c.r >= 0.88 and c.r <= 1.05 and c.g >= 0.91 and
			c.g <= 1.06 and c.b >= 0.84 and c.b <= 1.02,
			"all plants retain narrow believable pigmentation")
		varied[snappedf(c.r, 0.01)] = true
	t.check(varied.size() >= 6,
		"repeated flower/fern meshes do not all look identical")

	t.current = "native row-major 3D instance buffer layout"
	var origin := Vector2(224.0, -640.0)
	var transforms: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(1.25, 3.0, 4.5)),
		Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3(1.4, 0.9, 1.1)),
			Vector3(-3.25, 7.5, 2.25)),
	]
	var plain: PackedFloat32Array = Batches.packed_group(transforms)
	var colorful: PackedFloat32Array = Batches.packed_group(transforms, true, origin)
	t.eq(plain.size(), 24, "two transforms without tint need 12 floats each")
	t.eq(colorful.size(), 32, "two colored instances need 16 floats each")
	t.near(plain[3], 1.25, 0.00001,
		"transform row 0 packs translation x in the fourth float")
	t.near(plain[7], 3.0, 0.00001,
		"transform row 1 packs translation y in the eighth float")
	t.near(plain[11], 4.5, 0.00001,
		"transform row 2 packs translation z in the twelfth float")
	t.near(colorful[15], 1.0, 0.00001,
		"per-instance tint alpha remains opaque")
	t.eq(Color(colorful[12], colorful[13], colorful[14], colorful[15]),
		Batches.tint_at(origin + Vector2(1.25, 4.5)),
		"packed instance uses absolute world, not repeating local chunk coordinates")
	for i in 12:
		t.near(colorful[i], plain[i], 0.00001,
			"enabling color cannot change original transforms")

	t.current = "real GPU MultiMesh instances maintain draw budget and geometry"
	var parent := Node3D.new()
	var model := BoxMesh.new()
	model.size = Vector3(0.6, 1.0, 0.8)
	var plain_instances := Batches.add(parent, model, transforms, 90.0)
	var tinted_instances := Batches.add(parent, model, transforms, 90.0,
		false, 8.0, true, origin)
	t.eq(plain_instances.size(), 1,
		"sparse decorations still use one draw call")
	t.eq(tinted_instances.size(), 1,
		"colored flora stays inside one GPU instancing draw call")
	if plain_instances.size() == 1 and tinted_instances.size() == 1:
		var plain_mesh: MultiMesh = plain_instances[0].multimesh
		var color_mesh: MultiMesh = tinted_instances[0].multimesh
		t.check(not plain_mesh.use_colors,
			"stone/other props do not allocate extra color buffers")
		t.check(color_mesh.use_colors,
			"native MultiMesh color channel is active only for plants")
		t.eq(plain_mesh.instance_count, 2, "all original models are preserved")
		t.eq(color_mesh.instance_count, 2, "all colored models are preserved")
		for i in transforms.size():
			t.check(color_mesh.get_instance_transform(i).origin.distance_to(
				transforms[i].origin) < 0.0001,
				"one-upload native packed buffer preserves exact world placement")
			var c: Color = color_mesh.get_instance_color(i)
			t.check(c.r >= 0.88 and c.b <= 1.02,
				"native renderer receives bounded plant pigment")
		t.check(tinted_instances[0].visibility_range_end == 90.0,
			"spatial LOD and distance fade remain unchanged")
		# Native engine early-return for idempotent visible draw-count writes.
		color_mesh.visible_instance_count = 1
		for j in 64:
			color_mesh.visible_instance_count = 1
		t.eq(color_mesh.visible_instance_count, 1,
			"native no-op setter holds the existing LOD prefix")
		color_mesh.visible_instance_count = -1
		t.eq(color_mesh.visible_instance_count, -1,
			"restoring all instances still changes native GPU visibility")
	parent.free()

	t.current = "live streamed scene uses tinted foliage shaders"
	var source: String = (ChunkView as Script).source_code
	t.check(source.contains("var tint_plant: bool = SceneryBatches.colorful_plant(file)"),
		"chunk builder restricts color variation to actual green decor")
	t.check(source.contains("tint_plant, origin)"),
		"absolute world origin makes pigment stable after stream/reload")
	t.check((Foliage as Script).source_code.contains(
		"instance_tint = (instance_tinted || use_vertex_colors) ? COLOR.rgb"),
		"existing PBR foliage shader already consumes true instance color")
