extends RefCounted
## Real game resource batch initialization: transforms, tier tints,
## stock-Godot fallback, and all-or-nothing validation of caller input.
const Initializer = preload("res://scripts/client/resource_instance_initializer.gd")

func run(t) -> void:
	t.current = "resource MultiMesh initialization preserves placement and tier colors"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 4
	var placements: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(7, 0, 0))]
	var colors := PackedColorArray([
		Color.WHITE, Color(0.75, 0.5, 0.25, 1),
		Color(0.25, 0.5, 0.75, 1), Color(1, 1, 1, 1)])
	t.check(Initializer.initialize(mm, placements, colors),
		"small resource group initialized")
	for i in 4:
		t.eq(mm.get_instance_transform(i), placements[i], "resource position preserved")
		t.eq(mm.get_instance_color(i), colors[i], "original per-instance tint preserved")
	t.eq(mm.instance_count, 4, "allocation unchanged")
	t.eq(mm.visible_instance_count, -1, "all instances remain visible")
	t.eq(Initializer.MIN_NATIVE_BATCH, 12, "tiny groups avoid native batch overhead")

	t.current = "invalid initial payload never partially updates the buffer"
	var invalid := PackedColorArray([Color.RED])
	t.check(not Initializer.initialize(mm, placements, invalid), "length mismatch rejected")
	t.eq(mm.get_instance_color(0), colors[0], "failed request preserves color 0")
	t.eq(mm.get_instance_transform(3), placements[3], "failed request preserves final transform")
	var wrong: Array = []
	for placement in placements:
		wrong.append(placement)
	wrong[2] = Vector3.ZERO
	t.check(not Initializer.initialize(mm, wrong, colors), "wrong transform type rejected")
	t.eq(mm.get_instance_transform(2), placements[2], "wrong type does not mutate original")
	var nonfinite := colors.duplicate()
	nonfinite[1] = Color(INF, 0.0, 0.0, 1.0)
	t.check(not Initializer.initialize(mm, placements, nonfinite), "nonfinite tints rejected")
	t.eq(mm.get_instance_color(1), colors[1], "invalid tint does not partially overwrite colors")

	t.current = "dense chunks use native batching when available, fallback otherwise"
	var dense := MultiMesh.new()
	dense.transform_format = MultiMesh.TRANSFORM_3D
	dense.use_colors = true
	dense.mesh = BoxMesh.new()
	dense.instance_count = 24
	var dense_placements: Array[Transform3D] = []
	var dense_colors := PackedColorArray()
	for i in 24:
		dense_placements.append(Transform3D(Basis.IDENTITY, Vector3(float(i), 0, -1)))
		dense_colors.append(Color(0.25, 0.5, 1, 1) if i % 2 == 0 else Color(0.5, 0.75, 1, 1))
	t.check(Initializer.initialize(dense, dense_placements, dense_colors),
		"dense scene initializes with or without optional engine features")
	for i in 24:
		t.eq(dense.get_instance_transform(i), dense_placements[i], "dense transform preserved")
		t.eq(dense.get_instance_color(i), dense_colors[i], "dense pigment preserved")

	t.current = "missing color format fails without changing the buffer"
	var disabled := MultiMesh.new()
	disabled.instance_count = 1
	t.check(not Initializer.initialize(disabled,
		[Transform3D.IDENTITY], PackedColorArray([Color.WHITE])),
		"colors must be enabled explicitly")
	t.check(not disabled.use_colors, "validation never changes format")
	var empty := MultiMesh.new()
	empty.use_colors = true
	empty.instance_count = 0
	t.check(Initializer.initialize(empty, [], PackedColorArray()), "valid empty group accepted")
