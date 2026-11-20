extends SceneTree

const Foliage = preload("res://addons/visual_quality/foliage_chunks.gd")


func _initialize() -> void:
	var sample: PackedVector3Array = Foliage.sample_cell_positions(42, 2, 4, 12, 14.0, Vector2(28, 28), 10.0)
	var repeated: PackedVector3Array = Foliage.sample_cell_positions(42, 2, 4, 12, 14.0, Vector2(28, 28), 10.0)
	assert(sample == repeated, "Forest generation must be deterministic")
	assert(sample.size() == 12, "Unobstructed patch should contain all instances")
	assert(Foliage.cell_seed(42, 2, 4) != Foliage.cell_seed(42, 3, 4), "Cells need independent seeded layouts")
	for point in sample:
		assert(absf(point.x) <= 7.0)
		assert(absf(point.z) <= 7.0)
		assert(point.y == 0.0)
	var impossible: PackedVector3Array = Foliage.sample_cell_positions(42, 0, 0, 20, 12.0, Vector2.ZERO, 100.0)
	assert(impossible.is_empty(), "Fully excluded cells must exit without hanging")
	assert(Foliage.sample_cell_positions(42, 0, 0, 0, 12.0, Vector2.ZERO, 0.0).is_empty())
	assert(Foliage.sample_cell_positions(42, 0, 0, 1, 0.0, Vector2.ZERO, 0.0).is_empty())
	var packed: PackedVector3Array = Foliage.sample_cell_positions(42, 2, 4, 999, 14.0, Vector2(28, 28), 0.0)
	assert(packed.size() <= 64, "Density must be bounded for editor safety")
	print("ChunkedFoliage3D: 9 groups of checks passed")
	quit(0)
