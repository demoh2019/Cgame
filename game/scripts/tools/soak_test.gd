extends SceneTree
## Soak test CLI for the authoritative server.
##   godot --headless --path game --script res://scripts/tools/soak_test.gd -- \
##       --bots 40 --seconds 10 --scenario mixed --out /tmp/soak.json [--tick-rate 20] [--seed 1337] [--budget-ms X]
## Exit code 1 if p95 tick time exceeds the budget (default 1000/tick_rate * 0.5 ms) or a memory
## leak trend is detected (OLS slope above LEAK_SLOPE_BYTES_PER_S, over >= 5 samples).

const LoadGenerator = preload("res://scripts/tools/load_generator.gd")
const LEAK_SLOPE_BYTES_PER_S := 2.0 * 1024.0 * 1024.0
const MIN_LEAK_SAMPLES := 5


func _initialize() -> void:
	var args: Dictionary = _parse(OS.get_cmdline_user_args())
	var scenario_name: String = str(args.get("scenario", "mixed"))
	var overrides: Dictionary = {
		"bots": int(args.get("bots", 16)),
		"duration_s": float(args.get("seconds", 10.0)),
		"tick_rate": int(args.get("tick-rate", 20)),
		"seed": int(args.get("seed", 1337)),
	}
	var scenario: Dictionary = LoadGenerator.preset(scenario_name, overrides)
	var result: Dictionary = LoadGenerator.new().run(scenario)
	var budget_ms: float = float(args.get("budget-ms", 1000.0 / float(scenario["tick_rate"]) * 0.5))
	var p95: float = float(result["tick_ms"]["p95"])
	var slope: float = float(result["memory"]["slope_bytes_per_s"])
	var sample_count: int = (result["memory"]["samples"] as Array).size()
	var leak: bool = sample_count >= MIN_LEAK_SAMPLES and slope > LEAK_SLOPE_BYTES_PER_S
	var over_budget: bool = p95 > budget_ms
	result["verdict"] = {"budget_ms": budget_ms, "p95_over_budget": over_budget, "leak_detected": leak,
		"leak_threshold_bytes_per_s": LEAK_SLOPE_BYTES_PER_S, "scenario": scenario_name}
	var out_path: String = str(args.get("out", ""))
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			printerr("soak: cannot write %s" % out_path)
		else:
			file.store_string(JSON.stringify(result, "\t"))
			file.close()
	var ticks: Dictionary = result["tick_ms"]
	print("SOAK %s bots=%d sim=%.0fs wall=%.1fs tick_ms p50=%.3f p95=%.3f p99=%.3f max=%.3f budget=%.2f alive=%.1f zombies_max=%d cmds_ok=%d cmds_fail=%d mem_slope=%.0fB/s %s" % [
		scenario_name, int(result["bots"]), float(result["duration_s"]), float(result["wall_s"]),
		ticks["p50"], p95, ticks["p99"], ticks["max"], budget_ms, float(result["players_alive"]["mean"]),
		int(result["zombies"]["max"]), int(result["commands"]["ok_total"]), int(result["commands"]["fail_total"]),
		slope, "FAIL" if (over_budget or leak) else "PASS"])
	quit(1 if (over_budget or leak) else 0)


func _parse(argv: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	var i := 0
	while i < argv.size():
		var token: String = argv[i]
		if token.begins_with("--"):
			var key: String = token.substr(2)
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				parsed[key] = argv[i + 1]
				i += 1
			else:
				parsed[key] = "true"
		i += 1
	return parsed
