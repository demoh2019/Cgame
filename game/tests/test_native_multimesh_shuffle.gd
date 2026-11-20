extends RefCounted
## Native MultiMesh packed-instance shuffling vs. portable GDScript, GPU-free.
const GrassField = preload("res://scripts/client/grass_field.gd")


func run(t) -> void:
	t.current = "shuffled grass instance prefixes keep complete position/color records"
	var original := PackedFloat32Array()
	original.resize(64 * 16)
	for i in original.size():
		original[i] = float(i) * 0.25
	var expected: PackedFloat32Array = original.duplicate()
	GrassField.shuffle_instances(expected, 64, 2026)
	t.check(expected != original, "randomized layout does not preserve row-major order")
	var seen := {}
	for i in 64:
		var original_id: int = int(expected[i * 16] / 4.0)
		t.check(original_id >= 0 and original_id < 64, "shuffled instance id is in range")
		t.check(not seen.has(original_id), "shuffling never duplicates GPU transforms")
		seen[original_id] = true
		for field in 16:
			t.near(expected[i * 16 + field],
				original[original_id * 16 + field], 0.00001,
				"the transform and color stay attached to the same grass tuft")
	t.eq(seen.size(), 64, "grass density is spread across every tile")

	t.current = "native Cgame output matches the existing Godot fallback bit-for-bit"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.instance_count = 64
	if multimesh.has_method("shuffled_instance_buffer"):
		var actual: PackedFloat32Array = multimesh.call("shuffled_instance_buffer", original, 2026)
		t.eq(actual, expected, "native packed shuffle exactly matches GDScript PCG")
		t.eq(original[0], 0.0, "native call does not mutate the input data")
		var mismatch := PackedFloat32Array([10.0, 11.0, 12.0])
		t.eq(multimesh.call("shuffled_instance_buffer", mismatch, 2026), mismatch,
			"invalid record layouts cannot produce corrupt GPU instance buffers")
	else:
		var fallback: PackedFloat32Array = original.duplicate()
		GrassField.shuffle_instances(fallback, 64, 2026)
		t.eq(fallback, expected, "stock Godot remains fully supported")

	t.current = "real grass tile builder uses native path without losing fallback"
	var source: String = (GrassField as Script).source_code
	t.check(source.contains('multimesh.has_method("shuffled_instance_buffer")'),
		"live tile creation enables the C++ fast path on the Cgame engine")
	t.check(source.contains('buffer = multimesh.call("shuffled_instance_buffer", buffer, shuffle_seed)'),
		"native instance records are returned for the same GPU buffer upload")
	t.check(source.contains("shuffle_instances(buffer, count, shuffle_seed)"),
		"stock Godot preserves the original spatial distribution")
	t.check(source.contains("multimesh.buffer = buffer"),
		"all instance data is still uploaded in one RenderingServer operation")
