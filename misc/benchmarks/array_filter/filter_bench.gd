extends SceneTree

# Reproduce with identical debug/release flags and machine, baseline and patch.
# Example: godot --headless --script misc/benchmarks/array_filter/filter_bench.gd

const ELEMENTS := 50000
const ROUNDS := 80

func _run_case(source: Array[int], predicate: Callable, name: String) -> void:
	# Warm up callback compilation/caches.
	for warmup in 5:
		source.filter(predicate)
	var start_usec := Time.get_ticks_usec()
	var result: Array
	for i in ROUNDS:
		result = source.filter(predicate)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	print("ARRAY_FILTER_BENCH case=", name,
		" elements=", ELEMENTS,
		" rounds=", ROUNDS,
		" last_count=", result.size(),
		" avg_usec=", float(elapsed_usec) / ROUNDS)

func _initialize() -> void:
	var source: Array[int] = []
	source.resize(ELEMENTS)
	for i in ELEMENTS:
		source[i] = i
	_run_case(source, func(_value: int) -> bool: return false, "reject_all")
	_run_case(source, func(value: int) -> bool: return value % 2 == 0, "accept_even")
	_run_case(source, func(value: int) -> bool: return value == ELEMENTS - 1, "accept_last")
	_run_case(source, func(_value: int) -> bool: return true, "accept_all")
	quit()
