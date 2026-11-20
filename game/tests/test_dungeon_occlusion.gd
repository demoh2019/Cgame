extends RefCounted
## Conservative dungeon-only CPU occlusion must never hide open-world gameplay.

const DungeonOcclusion = preload("res://scripts/client/dungeon_occlusion.gd")


func run(t) -> void:
	t.current = "render backend and quality gate dungeon occlusion"
	t.check(not DungeonOcclusion.use_occlusion(3, "forward_plus", false),
		"open world never performs expensive CPU occlusion")
	t.check(not DungeonOcclusion.use_occlusion(0, "forward_plus", true),
		"Performance does not pay the CPU occlusion cost")
	t.check(DungeonOcclusion.use_occlusion(1, "forward_plus", true),
		"Balanced can cull walls behind underground walls")
	t.check(DungeonOcclusion.use_occlusion(3, "forward_plus", true),
		"Ultra uses occlusion indoors")
	t.check(DungeonOcclusion.use_occlusion(2, "mobile", true),
		"Mobile can benefit from reducing shader overdraw indoors")
	t.check(not DungeonOcclusion.use_occlusion(3, "gl_compatibility", true),
		"Compatibility stays on the conservative frustum-only path")

	t.current = "only large closed walls contribute occluders"
	t.check(DungeonOcclusion.supports_wall(AABB(Vector3.ZERO, Vector3(5.0, 2.2, 0.4))),
		"long solid wall is eligible")
	t.check(DungeonOcclusion.supports_wall(AABB(Vector3.ZERO, Vector3(0.4, 2.2, 5.0))),
		"wall aligned with Z axis is eligible")
	t.check(not DungeonOcclusion.supports_wall(AABB(Vector3.ZERO, Vector3(0.7, 2.0, 0.7))),
		"small pillar never hides an entire room")
	t.check(not DungeonOcclusion.supports_wall(AABB(Vector3.ZERO, Vector3(4.0, 0.2, 0.3))),
		"low floor tile cannot incorrectly occlude the scene")
	t.check(not DungeonOcclusion.supports_wall(AABB(Vector3.ZERO, Vector3(4.0, 2.0, 4.0))),
		"large square fixture cannot be mistaken for a wall")

	t.current = "inner occluder fits within actual wall bounds"
	var x_wall := AABB(Vector3(2.0, 1.0, 4.0), Vector3(5.0, 2.0, 0.6))
	var z_wall := AABB(Vector3(-3.0, 0.0, 1.0), Vector3(0.6, 2.0, 5.0))
	for wall in [x_wall, z_wall]:
		var inner: AABB = DungeonOcclusion.inner_bounds(wall)
		t.check(inner.size.x > 0.0 and inner.size.y > 0.0 and inner.size.z > 0.0,
			"conservative occluder keeps positive dimensions")
		t.check(inner.position.x >= wall.position.x and inner.end.x <= wall.end.x,
			"occluder remains inside horizontal X extents")
		t.check(inner.position.y >= wall.position.y and inner.end.y <= wall.end.y,
			"occluder remains below the physical wall top")
		t.check(inner.position.z >= wall.position.z and inner.end.z <= wall.end.z,
			"occluder remains inside horizontal Z extents")
		t.check(inner.size.y < wall.size.y, "isometric view can still see above walls")
	t.check(DungeonOcclusion.inner_bounds(x_wall).size.x >
		DungeonOcclusion.inner_bounds(x_wall).size.z,
		"X walls retain length as their longest occluding dimension")
	t.check(DungeonOcclusion.inner_bounds(z_wall).size.z >
		DungeonOcclusion.inner_bounds(z_wall).size.x,
		"Z walls retain length as their longest occluding dimension")
