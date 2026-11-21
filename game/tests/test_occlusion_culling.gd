extends RefCounted
## Software occlusion culling: depth rasteriser, Hi-Z pyramid, occluder selection.

const OcclusionRaster = preload("res://scripts/shared/occlusion_raster.gd")
const OccluderSimplifier = preload("res://scripts/shared/occluder_simplifier.gd")


func _make_raster() -> OcclusionRaster:
	# Camera at the origin looking down -Z; wall 20x10 at z -11..-10.5.
	var proj: Projection = Projection.create_perspective(70.0, 2.0, 0.1, 200.0)
	var r := OcclusionRaster.new()
	r.begin(proj, 256, 128)
	r.rasterize_occluder(OccluderSimplifier.box_occluder(AABB(Vector3(-10, -5, -11), Vector3(20, 10, 0.5))))
	return r


func run(t) -> void:
	t.current = "occlusion culling"
	var r: OcclusionRaster = _make_raster()
	t.check(r.occluder_triangles == 12 and r.pixels_written > 1000, "wall rasterised into the depth buffer")
	t.check(not r.is_visible(AABB(Vector3(-1, -1, -20), Vector3(2, 2, 2))), "box behind the wall is culled")
	t.check(r.is_visible(AABB(Vector3(22, -1, -21), Vector3(2, 2, 2))), "box beside the wall is visible")
	t.check(r.is_visible(AABB(Vector3(-1, -1, -6), Vector3(2, 2, 2))), "box in front of the wall is visible")
	t.check(r.is_visible(AABB(Vector3(12, -1, -21), Vector3(10, 2, 2))), "box peeking past the wall edge is visible")
	t.check(r.is_visible(AABB(Vector3(-1, -1, 5), Vector3(2, 2, 2))), "box behind the camera stays visible")
	t.check(r.is_visible(AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))), "box crossing the near plane stays visible")
	t.eq(r.tested, 6, "tested counter")
	t.eq(r.culled, 1, "culled counter")

	t.current = "occlusion hi-z"
	r.build_hiz()
	var ok := r.hiz_level_count() > 4
	for lv in range(1, r.hiz_level_count()):
		var sz: Vector2i = r.hiz_size(lv)
		var prev: Vector2i = r.hiz_size(lv - 1)
		for y in sz.y:
			for x in sz.x:
				var v: float = r.hiz_get(lv, x, y)
				for dy in 2:
					for dx in 2:
						var cx: int = mini(x * 2 + dx, prev.x - 1)
						var cy: int = mini(y * 2 + dy, prev.y - 1)
						if v < r.hiz_get(lv - 1, cx, cy):
							ok = false
	t.check(ok, "every Hi-Z texel is >= the max of its children")
	t.eq(r.hiz_size(r.hiz_level_count() - 1), Vector2i(1, 1), "pyramid ends at 1x1")
	t.check(r.hiz_get(r.hiz_level_count() - 1, 0, 0) == INF, "uncovered screen keeps the far value")

	t.current = "occlusion batch"
	var boxes: Array = [
		AABB(Vector3(-1, -1, -20), Vector3(2, 2, 2)),
		AABB(Vector3(22, -1, -21), Vector3(2, 2, 2)),
		AABB(Vector3(-1, -1, -6), Vector3(2, 2, 2)),
		AABB(Vector3(-3, -2, -30), Vector3(1, 1, 1)),
		AABB(Vector3(-1, -1, 5), Vector3(2, 2, 2)),
	]
	var batch: PackedByteArray = r.test_many(boxes)
	var same := batch.size() == boxes.size()
	for i in boxes.size():
		var bb: AABB = boxes[i]
		if (batch[i] == 1) != r.is_visible(bb):
			same = false
	t.check(same, "test_many matches single tests")
	t.eq(batch[0], 0, "batch culls hidden box")
	t.eq(batch[1], 1, "batch keeps visible box")

	t.current = "occlusion temporal"
	var proj: Projection = Projection.create_perspective(70.0, 2.0, 0.1, 200.0)
	r.begin(proj, 256, 128)
	r.temporal_reproject(proj)
	t.check(not r.is_visible(AABB(Vector3(-1, -1, -20), Vector3(2, 2, 2))), "reprojected previous depth still culls the hidden box")
	t.check(r.is_visible(AABB(Vector3(-1, -1, -6), Vector3(2, 2, 2))), "reprojection keeps near box visible")

	t.current = "occluder selection"
	var near_big := AABB(Vector3(-5, 0, -10), Vector3(10, 8, 2))
	var near_small := AABB(Vector3(0, 0, -6), Vector3(1, 1, 1))
	var far_big := AABB(Vector3(-5, 0, -150), Vector3(10, 8, 2))
	var picked: Array = OccluderSimplifier.select_occluders([far_big, near_small, near_big], Vector3.ZERO, 1)
	t.eq(picked.size(), 1, "budget respected")
	var best: AABB = picked[0]
	t.eq(best, near_big, "big near occluder wins")
	var two: Array = OccluderSimplifier.select_occluders([{"aabb": far_big}, {"aabb": near_big}], Vector3.ZERO, 5)
	var first: Dictionary = two[0]
	var first_box: AABB = first["aabb"]
	t.eq(first_box, near_big, "dictionary candidates ranked best first")
	t.eq(OccluderSimplifier.box_occluder(near_big).size(), 36, "box occluder has 12 triangles")
	var quad := QuadMesh.new()
	t.eq(OccluderSimplifier.from_mesh(quad, 1).size(), 3, "from_mesh caps triangle count")
