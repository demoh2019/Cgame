extends RefCounted
## City ring entrances, street-index parity and varied settlement shapes.
const CityLayout = preload("res://scripts/shared/city_layout.gd")


func run(t) -> void:
	t.current = "closed city ring connects to the side facing the regional road"
	var ring := PackedVector2Array([
		Vector2(10.0, 0.0), Vector2(0.0, 10.0),
		Vector2(-10.0, 0.0), Vector2(0.0, -10.0), Vector2(10.0, 0.0)])
	var ring_only: Array = [ring]
	t.eq(CityLayout.entrance_on_paths(ring_only, Vector2.LEFT), Vector2(-10.0, 0.0),
		"west road connects to the western side, not the ring seam")
	t.eq(CityLayout.entrance_on_paths(ring_only, Vector2.UP), Vector2(0.0, -10.0),
		"north road connects to the northern side, not the ring seam")
	t.eq(CityLayout.entrance_on_paths(ring_only, Vector2.ZERO), Vector2.ZERO,
		"missing road direction keeps the safe zero offset")

	t.current = "all settlement footprints have usable street entrances"
	for kind in CityLayout.TYPES:
		var layout: String = str(kind)
		var roads: Array = CityLayout.streets(layout, 64.0, 0.31)
		t.check(not roads.is_empty(), "%s creates traversable street paths" % layout)
		var entry: Vector2 = CityLayout.entrance_on_paths(roads, Vector2(1.0, 0.3))
		t.check(CityLayout.street_distance(entry, roads) < 0.001,
			"%s entrance lies on a real street centreline" % layout)

	t.current = "squared-distance scan agrees with indexed street clearance"
	var paths: Array = CityLayout.streets("organic", 80.0, 0.23)
	var index: Dictionary = CityLayout.index_streets(paths, 16.0, 8.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 727309
	for i in 100:
		var sample := Vector2(rng.randf_range(-90.0, 90.0),
			rng.randf_range(-90.0, 90.0))
		var distance: float = CityLayout.street_distance(sample, paths)
		for clearance in [1.0, 4.0, 7.0, 9.0]:
			var radius: float = float(clearance)
			t.eq(CityLayout.street_blocked(sample, radius, index),
				distance < radius, "indexed and scalar clearance agree for sample %d" % i)
	t.eq(CityLayout.street_distance(Vector2.ZERO, []), INF,
		"empty street network leaves an infinite distance")

	t.current = "oversized road segments stay accurate without huge grid allocation"
	var highway: Array = [PackedVector2Array([
		Vector2(-80000.0, 0.0), Vector2(80000.0, 0.0)])]
	var highway_index: Dictionary = CityLayout.index_streets(highway, 16.0, 8.0)
	t.eq((highway_index["cells"] as Dictionary).size(), 0,
		"giant segment does not allocate thousands of empty street buckets")
	t.eq((highway_index["overflow_segments"] as PackedInt32Array).size(), 1,
		"long segment is retained in a compact scalar fallback")
	for probe in [Vector2.ZERO, Vector2(0.0, 5.0), Vector2(0.0, 25.0),
			Vector2(79999.0, 1.0), Vector2(80050.0, 0.0)]:
		var expected_blocked: bool = CityLayout.street_distance(probe, highway) < 6.0
		t.eq(CityLayout.street_blocked(probe, 6.0, highway_index), expected_blocked,
			"overflow road clearance matches exact distance")
	t.check(not CityLayout.street_blocked(Vector2(NAN, 0.0), 3.0, highway_index),
		"nonfinite road probes cannot create bogus indexed collisions")
	t.check(not CityLayout.street_blocked(Vector2.ZERO, INF, highway_index),
		"nonfinite clearance cannot block settlement placement")
	var safe_index: Dictionary = CityLayout.index_streets(highway, NAN, INF)
	t.check(is_finite(float(safe_index["cell_size"])) and is_finite(float(safe_index["margin"])),
		"nonfinite index parameters are normalized")
