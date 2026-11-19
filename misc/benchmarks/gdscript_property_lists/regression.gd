extends SceneTree

# A real GDScript integration regression for editor property enumeration.
# Run after compiling the engine:
# godot --headless --path misc/benchmarks/gdscript_property_lists --script res://regression.gd

const DerivedScript = preload("res://derived.gd")
const WARMUP = 100
const BENCHMARK_ROUNDS = 5000


func _find_names(list: Array, target_names: Array[String]) -> Array[String]:
	var names: Array[String] = []
	for item in list:
		var name := String(item["name"])
		for target in target_names:
			if name == target or name.ends_with("/" + target):
				names.append(target)
	return names


func _check_sequence(observed: Array[String], expected: Array[String], description: String) -> bool:
	if observed != expected:
		push_error(description + ": expected " + str(expected) + ", got " + str(observed))
		return false
	return true


func _initialize() -> void:
	var instance = DerivedScript.new()
	var expected_members: Array[String] = ["child_first", "child_second", "base_first", "base_second"]
	var expected_statics: Array[String] = ["base_static_first", "base_static_second", "child_static_first", "child_static_second"]

	var member_names := _find_names(DerivedScript.get_script_property_list(), expected_members)
	var static_names := _find_names(DerivedScript.get_property_list(), expected_statics)

	var passed := _check_sequence(member_names, expected_members, "Script member property order")
	passed = _check_sequence(static_names, expected_statics, "Base-first static property order") and passed
	if not passed:
		instance.free()
		quit(1)
		return

	var start_usec := Time.get_ticks_usec()
	for i in WARMUP:
		DerivedScript.get_script_property_list()
		DerivedScript.get_property_list()
	start_usec = Time.get_ticks_usec()
	for i in BENCHMARK_ROUNDS:
		DerivedScript.get_script_property_list()
		DerivedScript.get_property_list()
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	print("GDSCRIPT_PROPERTY_LIST_PERF rounds=", BENCHMARK_ROUNDS,
			" mean_pair_us=", float(elapsed_usec) / BENCHMARK_ROUNDS)
	instance.free()
	quit(0)
