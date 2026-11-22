extends RefCounted
## Engine GPU per-instance MultiMesh culling and density LOD: resource API, facade, game wiring.
const GpuCulling = preload("res://scripts/native/cgame_gpu_culling.gd")
const GroundPlants = preload("res://scripts/client/ground_plants.gd")


func run(t) -> void:
	t.current = "MultiMesh GPU culling resource API"
	var engine_has_it: bool = ClassDB.class_has_method("MultiMesh", "set_gpu_culling")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 4
	if engine_has_it:
		t.eq(mm.get("gpu_culling"), false, "off by default: every instance is drawn as before")
		t.eq(mm.get("gpu_culling_min_density"), 1.0, "density LOD off by default")
		mm.set("gpu_culling_distance", -5.0)
		t.eq(mm.get("gpu_culling_distance"), 0.0, "negative range clamps to unlimited")
		mm.set("gpu_culling_min_density", 3.0)
		t.eq(mm.get("gpu_culling_min_density"), 1.0, "density clamps to 1")
		mm.set("gpu_culling_min_density", -1.0)
		t.eq(mm.get("gpu_culling_min_density"), 0.0, "density clamps to 0")
	else:
		t.check(not GpuCulling.available(), "facade reports the feature missing on a stock build")

	t.current = "facade configures range and density LOD"
	var enabled: bool = GpuCulling.enable(mm, 60.0, 90.0, 0.3)
	t.eq(enabled, GpuCulling.available(), "enable() reports whether the engine culls")
	if enabled:
		t.eq(mm.get("gpu_culling"), true, "culling on")
		t.eq(mm.get("gpu_culling_distance"), 60.0, "range")
		t.eq(mm.get("gpu_culling_density_start"), 60.0, "thinning cannot start past the range")
		t.near(float(mm.get("gpu_culling_min_density")), 0.3, 0.0001, "far density")
	t.check(not GpuCulling.enable(null, 10.0), "null multimesh is ignored")

	t.current = "quality presets thin foliage, not props"
	t.check(GroundPlants.quality_far_density(1) < GroundPlants.quality_far_density(3), "Balanced thins more than Ultra")
	for level in 4:
		var density: float = GroundPlants.quality_far_density(level)
		t.check(density > 0.0 and density <= 1.0, "far density in (0, 1] at level %d" % level)
	var plants: String = FileAccess.get_file_as_string("res://scripts/client/ground_plants.gd")
	t.check(plants.contains('var thin: bool = not info.has("files")'), "scanned props keep every instance")
