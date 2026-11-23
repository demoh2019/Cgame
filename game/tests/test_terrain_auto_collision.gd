extends RefCounted
## Actual Albion world-height sampler -> native editable terrain collider.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const TerrainAuthoring = preload("res://scripts/client/terrain_collision_authoring.gd")


func run(t) -> void:
	t.current = "Albion terrain collision authoring"
	var world := WorldGen.new(1337)
	var unsupported := TerrainAuthoring.build_patch(world, Vector2.ZERO, 0, 1.0)
	t.eq(unsupported, null, "zero-cell terrain is safely rejected")
	t.eq(TerrainAuthoring.build_patch(world, Vector2.ZERO, 16, NAN),
		null, "nonfinite spacing is rejected")
	if not ClassDB.class_exists("HeightmapTerrain3D"):
		t.eq(TerrainAuthoring.build_patch(world, Vector2.ZERO), null,
			"stock Godot safely omits native editor-only terrain collision")
		return
	var origin := Vector2(120.0, 80.0)
	var terrain: Node3D = TerrainAuthoring.build_patch(world, origin, 16, 2.0, 2)
	t.check(terrain != null, "real world height field creates native terrain")
	if terrain == null:
		return
	var heightmap = terrain.get("heightmap")
	t.eq(heightmap.get_width(), 17, "height data has 17 columns")
	t.eq(heightmap.get_depth(), 17, "height data has 17 rows")
	t.near(float(heightmap.get_height(8, 8)),
		float(world.height_at(origin.x + 16.0, origin.y + 16.0)), 0.0001,
		"native terrain uses real Albion world heights")
	t.eq(int(terrain.call("get_auto_collision_triangle_count")), 128,
		"16-cell authoring preview has bounded 8x8 collider")
	var before = terrain.call("get_auto_collision_shape")
	t.check(before != null, "a physical Shape3D is generated")
	var old: float = float(heightmap.get_height(8, 8))
	heightmap.set_height(8, 8, old + 3.0)
	var after = terrain.call("get_auto_collision_shape")
	t.check(after != null and after != before,
		"editing Albion terrain rebuilds the collision shape")
	t.eq(int(terrain.call("get_auto_collision_triangle_count")), 128,
		"sculpted terrain stays inside collision budget")
	heightmap.apply_color_brush(Vector2(8, 8), 3.0, Color.RED, 1.0)
	t.check(terrain.call("get_auto_collision_shape") == after,
		"terrain color paint does not trigger expensive physics rebuild")
	terrain.call("set_auto_collision_enabled", false)
	t.eq(int(terrain.call("get_auto_collision_triangle_count")), 0,
		"disabling authoring physics removes collision without losing terrain")
	terrain.free()
