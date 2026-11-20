extends RefCounted
## No fabricated GPU FPS: screenshot demos report bounded CPU frame pacing.

const RenderBenchmark = preload("res://scripts/client/render_benchmark.gd")


func run(t) -> void:
	t.current = "deterministic sorted CPU frame-time percentiles"
	var source: Array[float] = [40.0, 10.0, 50.0, 20.0, 30.0]
	var original: Array[float] = source.duplicate()
	var summary: Dictionary = RenderBenchmark.summarize(source)
	t.eq(summary["count"], 5, "counts actual valid frame samples")
	t.near(float(summary["p50_ms"]), 30.0, 0.00001,
		"p50 is not the most recent frame")
	t.near(float(summary["p95_ms"]), 48.0, 0.00001,
		"95th percentile reveals slow-frame tails")
	t.near(float(summary["p99_ms"]), 49.6, 0.00001,
		"99th percentile interpolates the worst 1% correctly")
	t.near(float(summary["mean_ms"]), 30.0, 0.00001,
		"mean uses the full set of actual frame durations")
	t.near(float(summary["one_percent_low_fps"]), 1000.0 / 49.6, 0.00001,
		"1%-low FPS derives from the slowest percentile")
	t.eq(source, original, "profiling never reorders the caller's recording")
	var text_line: String = RenderBenchmark.describe(summary)
	t.check(text_line.contains("p50") and text_line.contains("p95") and
		text_line.contains("p99") and text_line.contains("CPU, not GPU"),
		"console output is complete and honestly identifies CPU timing")

	t.current = "empty, invalid and single-frame benchmarks are safe"
	var bad: Array[float] = [0.0, -1.0, NAN, INF, -INF]
	var empty: Dictionary = RenderBenchmark.summarize(bad)
	t.eq(empty["count"], 0, "invalid values cannot create fictitious FPS")
	t.eq(empty["one_percent_low_fps"], 0.0, "empty capture never divides by zero")
	t.check(RenderBenchmark.describe(empty).contains("no valid samples"),
		"empty output clearly reports missing data")
	var one: Array[float] = [17.0]
	var single: Dictionary = RenderBenchmark.summarize(one)
	t.near(single["p50_ms"], 17.0, 0.00001, "one sample has a defined median")
	t.near(single["p95_ms"], 17.0, 0.00001, "one sample has a defined tail")
	t.near(single["p99_ms"], 17.0, 0.00001, "one sample has a defined worst tail")
	var mixed: Array[float] = [11.0, 0.0, NAN, 19.0, INF, 2000.0]
	var valid: Dictionary = RenderBenchmark.summarize(mixed)
	t.eq(valid["count"], 2, "invalid, non-positive and extreme stalls are ignored")
	t.near(valid["p50_ms"], 15.0, 0.00001,
		"bad samples never pollute comparisons across visual presets")

	t.current = "the real screenshot demo calls the benchmark"
	var client_code: String = FileAccess.get_file_as_string(
		"res://scripts/client/online_main.gd")
	t.check(client_code.contains("RenderBenchmark.summarize(_frame_ms)"),
		"online scene measures its actual scene render loop")
	t.check(client_code.contains("RenderBenchmark.describe(pace)"),
		"the benchmark writes the result into existing demo logs")
