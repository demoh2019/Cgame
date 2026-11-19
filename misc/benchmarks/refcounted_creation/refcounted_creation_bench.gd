extends SceneTree

# Compare baseline / patched executables with identical build flags.
# This measures GDScript ClassDB construction, NOT isolated C++ memnew() time.

const WARMUP := 10000
const ITERATIONS := 120000

func _exercise(count: int) -> void:
	for i in count:
		var value: RefCounted = RefCounted.new()
		# Prevent the compiler from removing the construction.
		if value.get_reference_count() == -1:
			push_error("Unexpected reference count")

func _initialize() -> void:
	_exercise(WARMUP)
	var start := Time.get_ticks_usec()
	_exercise(ITERATIONS)
	var elapsed := Time.get_ticks_usec() - start
	print("REFCOUNTED_BENCH total_usec=", elapsed,
		" iterations=", ITERATIONS,
		" avg_usec=", float(elapsed) / ITERATIONS)
	quit()
