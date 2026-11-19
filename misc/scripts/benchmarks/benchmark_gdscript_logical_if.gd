extends SceneTree

# Standalone microbenchmark for boolean short-circuit branch lowering.
# Run: godot --headless --script res://misc/scripts/benchmarks/benchmark_gdscript_logical_if.gd
const RUNS := 200000

func _initialize() -> void:
	var seed_value: int = Time.get_ticks_usec()
	var a: bool = (seed_value & 1) == 0
	var b: bool = (seed_value & 2) == 0
	var matches: int = 0
	var begin := Time.get_ticks_usec()
	for i in RUNS:
		if a and b:
			matches += 1
	var and_duration := Time.get_ticks_usec() - begin
	begin = Time.get_ticks_usec()
	for i in RUNS:
		if a or b:
			matches += 1
	var or_duration := Time.get_ticks_usec() - begin
	print("GDScript logical if: ", RUNS, " iterations; and=", and_duration, " usec; or=", or_duration, " usec; matches=", matches)
	quit()
