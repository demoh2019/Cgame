extends RefCounted
## Checks the geometry budget and hysteresis of the grass LOD used by ChunkView.

const GrassField = preload("res://scripts/client/grass_field.gd")


func run(t) -> void:
	t.current = "grass geometry LOD"
	var previous_triangles := 999999
	for blades in GrassField.LOD_BLADES:
		var mesh: ArrayMesh = GrassField.clump_mesh(blades)
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var crossed: int = blades if blades >= 18 else (ceili(float(blades) * 0.5) if blades >= 9 else 0)
		var ribbons: int = blades + crossed
		var petal_vertices: int = vertices.size() - ribbons * 6
		t.check(petal_vertices >= 0 and petal_vertices % 20 == 0,
			"%d blades have two six-vertex ribbons near, plus optional flower petals" % blades)
		var flower_heads: int = petal_vertices / 20
		t.eq(indices.size(), ribbons * 12 + flower_heads * 30,
			"%d blades have four triangles per ribbon plus five-petal flower heads" % blades)
		t.check(indices.size() < previous_triangles, "lower LOD draws fewer triangles")
		previous_triangles = indices.size()
	t.check(GrassField.clump_mesh(18) == GrassField.clump_mesh(18), "near mesh is reused across tiles")
	t.check(GrassField.clump_mesh(4) == GrassField.clump_mesh(4), "far mesh is reused across tiles")

	t.current = "grass blades have real side-on volume"
	var near_arrays: Array = GrassField.clump_mesh(18).surface_get_arrays(0)
	var near_vertices: PackedVector3Array = near_arrays[Mesh.ARRAY_VERTEX]
	var near_uvs: PackedVector2Array = near_arrays[Mesh.ARRAY_TEX_UV]
	var near_normals: PackedVector3Array = near_arrays[Mesh.ARRAY_NORMAL]
	var at := 0
	var total_root_width := 0.0
	var curved_count := 0
	var angled_normals := 0
	for blade in 18:
		var root_middle: Vector3 = (near_vertices[at] + near_vertices[at + 1]) * 0.5
		var shoulder_middle: Vector3 = (near_vertices[at + 2] + near_vertices[at + 3]) * 0.5
		var tip_middle: Vector3 = (near_vertices[at + 4] + near_vertices[at + 5]) * 0.5
		var axis_front: Vector3 = (near_vertices[at + 1] - near_vertices[at]).normalized()
		var axis_side: Vector3 = (near_vertices[at + 7] - near_vertices[at + 6]).normalized()
		var root_width: float = near_vertices[at].distance_to(near_vertices[at + 1])
		var shoulder_width: float = near_vertices[at + 2].distance_to(near_vertices[at + 3])
		var tip_width: float = near_vertices[at + 4].distance_to(near_vertices[at + 5])
		total_root_width += root_width
		t.check(absf(axis_front.dot(axis_side)) < 0.4,
			"crossed ribbons give blade %d a broad edge-on silhouette" % blade)
		t.check(shoulder_width > tip_width, "grass widens at the shoulder and tapers to the tip")
		if shoulder_middle.distance_to(root_middle.lerp(tip_middle, 0.54)) > 0.004:
			curved_count += 1
		if near_normals[at].distance_to(Vector3.UP) > 0.1:
			angled_normals += 1
		at += 12
		# Five four-vertex petals are interleaved after the crossed flower blade.
		if at < near_vertices.size() and near_uvs[at].y > 1.2:
			at += 20
	t.eq(at, near_vertices.size(), "every flower and crossed blade has a complete indexed mesh")
	t.check(total_root_width / 18.0 > 0.035,
		"near grass blades have more width than the old paper-thin quads")
	t.check(curved_count >= 9, "at least half the blades have non-linear bends")
	t.check(angled_normals >= 9, "normals vary around the grass")
	t.check(GrassField.SHADER_CODE.contains("MODEL_MATRIX * vec4(NORMAL, 0.0)"),
		"shader shades the two real ribbon orientations separately")

	t.current = "grass edge-on detail is budgeted by LOD"
	var near_mesh: ArrayMesh = GrassField.clump_mesh(18)
	var middle_mesh: ArrayMesh = GrassField.clump_mesh(9)
	var far_mesh: ArrayMesh = GrassField.clump_mesh(4)
	var near_size: int = (near_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	var middle_size: int = (middle_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	var far_size: int = (far_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	t.check(near_size > middle_size and middle_size > far_size,
		"crossed geometry is limited to nearby LODs")
	t.check(GrassField.BLADE_WIDTH_SCALE >= 1.2,
		"blade width is large enough for crossed ribbons to remain visible")

	t.current = "grass LOD hysteresis"
	t.eq(GrassField.lod_for_distance(0.0), 0, "close view uses highest geometry")
	t.eq(GrassField.lod_for_distance(26.0, 0), 0, "stay near until upper boundary")
	t.eq(GrassField.lod_for_distance(27.0, 0), 1, "cross upper boundary to medium")
	t.eq(GrassField.lod_for_distance(40.0, 1), 1, "medium stays stable")
	t.eq(GrassField.lod_for_distance(45.0, 1), 2, "switch to distant mesh")
	t.eq(GrassField.lod_for_distance(41.0, 2), 2, "far mesh does not thrash")
	t.eq(GrassField.lod_for_distance(39.0, 2), 1, "return to medium")
	t.eq(GrassField.lod_for_distance(21.0, 1), 0, "return to close mesh")
	t.eq(GrassField.lod_for_distance(100.0, 0), 2, "large camera jumps can skip tiers")
	t.eq(GrassField.lod_for_distance(0.0, 2), 0, "camera teleport restores detail")


	t.current = "screen-space grass LOD respects resolution and FOV"
	t.near(GrassField.screen_lod_scale(720.0, 38.0), 1.0, 0.0001,
		"reference 720p camera matches original LOD authoring")
	t.check(GrassField.screen_lod_scale(1080.0, 38.0) > 1.0,
		"1080p camera retains high-detail blades farther away")
	t.check(GrassField.screen_lod_scale(360.0, 38.0) < 1.0,
		"low resolution reduces subpixel grass geometry")
	t.check(GrassField.screen_lod_scale(720.0, 55.0) < 1.0,
		"a wider field of view chooses distant detail earlier")
	t.check(GrassField.screen_lod_scale(720.0, 24.0) > 1.0,
		"narrow focal length preserves close-detail silhouette")
	t.eq(GrassField.screen_lod_scale(720.0, NAN), 1.0,
		"invalid camera FOV does not break grass quality")
	t.eq(GrassField.screen_lod_scale(0.0, 38.0), 1.0,
		"minimized window keeps a safe fallback")
	t.check(GrassField.screen_lod_scale(100000.0, 10.0) <= 1.6,
		"high-resolution GPU cost remains bounded")
	t.eq(GrassField.lod_for_distance(30.0, 0, 1.5), 0,
		"Ultra preserves close blades at the same viewing distance")
	t.eq(GrassField.lod_for_distance(60.0, 0, 1.5), 1,
		"larger pixel budget keeps the middle mesh")
	t.eq(GrassField.lod_for_distance(60.0, 0, 0.65), 2,
		"Performance reaches low triangle budget earlier")
	t.eq(GrassField.lod_for_distance(-1.0, 2), 2,
		"invalid distance conservatively preserves the previous LOD")

	t.current = "camera-stable LOD update budget"
	t.check(GrassField.needs_lod_refresh(Vector2.ZERO, -1.0, -1,
		Vector2.ZERO, 1.0, 0), "first update always initializes the cache")
	t.check(not GrassField.needs_lod_refresh(Vector2.ZERO, 1.0, 10,
		Vector2.ZERO, 1.0, 10), "a stationary camera skips repeated tile scans")
	t.check(not GrassField.needs_lod_refresh(Vector2.ZERO, 1.0, 10,
		Vector2(0.2, 0.0), 1.0, 10), "tiny camera jitter does not trigger LOD work")
	t.check(GrassField.needs_lod_refresh(Vector2.ZERO, 1.0, 10,
		Vector2(0.25, 0.0), 1.0, 10), "a real camera move updates LOD")
	t.check(GrassField.needs_lod_refresh(Vector2.ZERO, 1.0, 10,
		Vector2.ZERO, 1.1, 10), "FOV or quality changes invalidate LOD")
	t.check(GrassField.needs_lod_refresh(Vector2.ZERO, 1.0, 10,
		Vector2.ZERO, 1.0, 11), "new grass tiles invalidate stationary camera cache")

	t.current = "quality-relative density"
	t.check(GrassField.visible_count_for_distance(1000, 34.0, 1.5)
		> GrassField.visible_count_for_distance(1000, 34.0),
		"high-resolution grass retains coverage longer")
	t.check(GrassField.visible_count_for_distance(1000, 34.0, 0.65)
		< GrassField.visible_count_for_distance(1000, 34.0),
		"lower-res grass shades fewer distant blades")
	t.eq(GrassField.visible_count_for_distance(1000, 34.0, NAN),
		GrassField.visible_count_for_distance(1000, 34.0),
		"invalid scale is treated as the original balanced budget")
	t.eq(GrassField.visible_count_for_distance(1000, 0.0, 0.65), 1000,
		"even Performance retains all grass right under the camera")

	t.current = "distance-aware grass density keeps nearby detail and limits far GPU instances"
	t.eq(GrassField.visible_count_for_distance(1000, 0.0), 1000, "close grass is fully populated")
	t.eq(GrassField.visible_count_for_distance(1000, 18.0), 1000, "density starts at the designed distance")
	t.eq(GrassField.visible_count_for_distance(1000, 34.0), 720, "first fade removes only distant instances")
	t.eq(GrassField.visible_count_for_distance(1000, 35.0), 720, "transitions have no hard density jump")
	t.eq(GrassField.visible_count_for_distance(1000, 55.0), 400, "far grass uses forty percent")
	t.eq(GrassField.visible_count_for_distance(1000, 500.0), 400, "far density is bounded")
	t.eq(GrassField.visible_count_for_distance(0, 25.0), 0, "empty tiles remain empty")
	t.eq(GrassField.visible_count_for_distance(1, 100.0), 1, "one real tuft is never lost")
	t.eq(GrassField.visible_count_for_distance(100, -1.0), 100, "invalid negative distance stays conservative")
	t.eq(GrassField.visible_count_for_distance(100, NAN), 100, "invalid distance does not hide grass")
	var last_count := 1000
	for distance in range(0, 100, 2):
		var current: int = GrassField.visible_count_for_distance(1000, float(distance))
		t.check(current <= last_count and current >= 400,
			"density decreases monotonically with distance")
		last_count = current

	t.current = "shuffled instance prefixes preserve uniform spatial coverage and colors"
	var records := PackedFloat32Array()
	records.resize(64 * 16)
	for id in 64:
		for field in 16:
			records[id * 16 + field] = float(id * 32 + field)
	var shuffled: PackedFloat32Array = records.duplicate()
	var repeated: PackedFloat32Array = records.duplicate()
	GrassField.shuffle_instances(shuffled, 64, 2026)
	GrassField.shuffle_instances(repeated, 64, 2026)
	t.eq(shuffled, repeated, "same seed yields deterministic placement draw order")
	t.check(shuffled != records, "instances are no longer in row-major placement order")
	var seen: Dictionary = {}
	for id in 64:
		var original_id: int = int(shuffled[id * 16]) / 32
		t.check(original_id >= 0 and original_id < 64, "all shuffled rows have valid origins")
		t.check(not seen.has(original_id), "shuffle does not duplicate plant positions")
		seen[original_id] = true
		for field in 16:
			t.eq(shuffled[id * 16 + field], float(original_id * 32 + field),
				"tint and transform always travel together")
	t.eq(seen.size(), 64, "all physical grass placements are preserved")

	t.current = "grass vertex shader fade budget"
	var wind_shader: String = GrassField.SHADER_CODE
	t.check(wind_shader.contains("if (shrink > 0.001)"), "fully-faded blades skip trig after distance LOD")
	t.check(wind_shader.contains("sheen = 0.0;"), "fully-faded blades have a deterministic zero-gust fallback")
	t.check(wind_shader.contains("VERTEX.y *= shrink;"), "old gradual fade is retained")
