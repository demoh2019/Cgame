extends RefCounted
## Grass is flattened under objects and walkers instead of growing through them.
const PlantInteraction = preload("res://scripts/client/plant_interaction.gd")
const GrassField = preload("res://scripts/client/grass_field.gd")


func run(t) -> void:
	t.current = "shader flattens blades inside a footprint"
	var include := FileAccess.get_file_as_string("res://assets/shaders/plant_interaction.gdshaderinc")
	t.check(include.contains("float aa_plant_crush(vec2 root)"), "crush function exists")
	t.check(GrassField.SHADER_CODE.contains("aa_plant_crush(root.xz)"), "grass applies the crush")
	for i in PlantInteraction.MAX_CRUSHERS:
		t.check(ProjectSettings.has_setting("shader_globals/aa_plant_crush_%d" % i), "crusher slot %d registered" % i)
	t.check(ProjectSettings.has_setting("shader_globals/aa_plant_crush_count"), "crusher count registered")

	t.current = "nearest objects win the limited slots"
	var sources: Array = []
	for i in 12:
		sources.append(["zombie", {"x": float(i) * 3.0, "z": 0.0}])
	sources.append(["campfire", {"x": 0.5, "z": 0.5}])
	sources.append(["campfire", {"x": 500.0, "z": 0.0}]) # Far beyond the grass.
	sources.append(["unknown", {"x": 0.0, "z": 0.0}])
	sources.append(["bag", {"x": INF, "z": 0.0}])
	sources.append(["bag", {"z": 0.0}])
	var picked: Array = PlantInteraction.pick_crushers(Vector2.ZERO, sources)
	t.eq(picked.size(), PlantInteraction.MAX_CRUSHERS, "never more than the shader slots")
	var has_fire := false
	for crusher in picked:
		var v: Vector4 = crusher
		t.check(Vector2(v.x, v.y).length() <= PlantInteraction.CRUSH_RANGE, "only nearby objects")
		if is_equal_approx(v.z, float(PlantInteraction.FOOTPRINTS["campfire"].x)):
			has_fire = true
	t.check(has_fire, "the campfire beside you flattens its grass")
	t.eq(PlantInteraction.pick_crushers(Vector2.ZERO, []).size(), 0, "nothing nearby, nothing flattened")

	t.current = "no grass grows out of static world objects"
	var chunk := {"crates": [{"x": 5.0, "z": 5.0, "radius": 0.6}], "props": [{"x": 20.0, "z": 3.0, "radius": 1.2}],
		"structures": [{"x": 40.0, "z": 40.0, "radius": 6.0}], "nodes": [{"x": 1.0, "z": 1.0}]}
	var prints: PackedVector3Array = GrassField.footprints(chunk)
	t.eq(prints.size(), 3, "objects with a radius leave a footprint")
	t.check(GrassField.under_object(5.1, 5.0, prints), "no tuft inside a crate")
	t.check(GrassField.under_object(41.0, 42.0, prints), "no tuft inside a ruin")
	t.check(not GrassField.under_object(8.0, 8.0, prints), "grass still grows around objects")
