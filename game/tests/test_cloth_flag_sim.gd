extends RefCounted
## Outpost banners: native XPBD cloth on High/Ultra, shader cloth below, rigid flag on Low.

const ClothFlag = preload("res://scripts/client/cloth_flag.gd")


func _flag() -> MeshInstance3D:
	var flag := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 1.5, 0.06)
	flag.mesh = box
	flag.position = Vector3(1.3, 6.1, 0.0)
	flag.material_override = StandardMaterial3D.new()
	return flag


func run(t) -> void:
	var native: bool = ClassDB.class_exists("ClothInstance3D") and ClassDB.class_exists("CgameXPBDCloth")

	t.current = "tier selection"
	t.check(not ClothFlag.can_simulate(0) and not ClothFlag.can_simulate(1), "Low/Balanced never simulate")
	t.eq(ClothFlag.can_simulate(2), native, "High simulates exactly when the native classes exist")
	var low := _flag()
	t.eq(ClothFlag.apply(low, 0), "rigid", "Low keeps the rigid flag")
	t.check(low.mesh is BoxMesh, "rigid flag mesh untouched")
	low.free()
	var mid := _flag()
	t.eq(ClothFlag.apply(mid, 1), "shader", "Balanced uses the shader cloth")
	t.check(mid.material_override is ShaderMaterial, "shader material installed")
	t.check(mid.get_node_or_null(ClothFlag.CLOTH_NODE) == null, "no cloth node on the shader path")
	mid.free()

	t.current = "wind mapping"
	var calm := ClothFlag.wind_vector(Vector3.ZERO)
	t.near(calm.length(), ClothFlag.WIND_BASE, 0.001, "calm weather still has a light breeze")
	var gale := ClothFlag.wind_vector(Vector3(1.0, 0.0, 1.0))
	t.near(gale.x, ClothFlag.WIND_BASE + ClothFlag.WIND_SCALE, 0.001, "vegetation wind xy maps onto world xz")
	t.near(gale.y, 0.0, 0.001, "no vertical wind")
	var grid := ClothFlag.sim_grid(3)
	t.check(grid.x >= ClothFlag.segments(3) and grid.y >= 2, "Ultra grid at least as dense as the shader mesh")

	if not native:
		t.current = "simulated (skipped: native cgame_softbody missing)"
		var fallback := _flag()
		t.eq(ClothFlag.apply(fallback, 3), "shader", "without the module Ultra falls back to the shader cloth")
		fallback.free()
		return

	t.current = "simulated banner"
	var tree := Engine.get_main_loop() as SceneTree
	var host := Node3D.new()
	var flag := _flag()
	var material: Material = flag.material_override
	t.eq(ClothFlag.apply(flag, 3), "simulated", "Ultra gets the native cloth")
	var node := flag.get_node_or_null(ClothFlag.CLOTH_NODE) as GeometryInstance3D
	t.check(node != null and node.is_class("ClothInstance3D"), "ClothInstance3D child installed")
	t.check(flag.mesh == null, "rigid box hidden")
	t.check(flag.material_override == material and node.material_override == material, "tint material shared with the cloth")
	t.near(flag.position.x, 0.1, 0.001, "pinned at the pole like the shader path")
	host.add_child(flag)
	tree.root.add_child(host)
	if not node.is_inside_tree(): # The test runner tree is not running yet; build as tree_entered would.
		ClothFlag.build_grid(node)
	var cloth: Object = node.call("get_cloth")
	var expected: int = (grid.x + 1) * (grid.y + 1)
	t.eq(int(cloth.call("particle_count")), expected, "grid built when entering the tree")
	cloth.set("wind", ClothFlag.wind_vector(Vector3(0.0, 1.0, 1.0)))
	var pole0: Vector3 = (cloth.call("positions") as PackedVector3Array)[cloth.call("index_of", 0, 0)]
	var free_index: int = cloth.call("index_of", grid.x, grid.y / 2)
	var free0: Vector3 = (cloth.call("positions") as PackedVector3Array)[free_index]
	for _i in 90:
		node.call("simulate", 1.0 / 60.0)
	var positions: PackedVector3Array = cloth.call("positions")
	t.near(positions[cloth.call("index_of", 0, 0)].distance_to(pole0), 0.0, 0.001, "pole edge stays pinned")
	t.check(positions[free_index].z > free0.z + 0.05, "free edge is blown downwind (+z)")
	t.check(positions[free_index].is_finite(), "simulation stays finite")
	ClothFlag.update_wind(flag)
	t.check((cloth.get("wind") as Vector3).length() > 0.0, "update_wind feeds the weather wind")
	host.free()
