extends RefCounted
## Load generator: behaviour mixes complete with sane metrics, PvP produces combat, runs are deterministic.

const LoadGenerator = preload("res://scripts/tools/load_generator.gd")


func _small(name: String, bots: int = 8, seconds: float = 3.0, seed_value: int = 77) -> Dictionary:
	return LoadGenerator.new().run(LoadGenerator.preset(name, {"bots": bots, "duration_s": seconds, "seed": seed_value}))


func _check_metrics(t, r: Dictionary, label: String) -> void:
	var tm: Dictionary = r["tick_ms"]
	t.eq(int(r["ticks"]), 60, label + " ran 3s at 20Hz")
	for key in ["p50", "p95", "p99", "max", "mean"]:
		t.check(is_finite(float(tm[key])) and float(tm[key]) >= 0.0, "%s tick %s finite" % [label, key])
	t.check(float(tm["p50"]) <= float(tm["p95"]) and float(tm["p95"]) <= float(tm["p99"]) and float(tm["p99"]) <= float(tm["max"]),
		label + " percentiles ordered")
	t.check(is_finite(float(r["events"]["per_tick_mean"])), label + " events per tick finite")
	t.check(int(r["players_alive"]["min"]) >= 0, label + " alive tracked")
	t.check((r["memory"]["samples"] as Array).size() >= 3, label + " memory sampled")
	t.check(is_finite(float(r["memory"]["slope_bytes_per_s"])), label + " memory slope finite")


func run(t) -> void:
	t.current = "mix scenarios"
	var results: Dictionary = {}
	for name in ["pvp", "pve", "mixed"]:
		results[name] = _small(name)
		_check_metrics(t, results[name], name)

	t.current = "pvp combat"
	var pvp: Dictionary = results["pvp"]
	var attacks: int = int(pvp["commands"]["ok"].get("attack", 0))
	for key in pvp["commands"]["fail"]:
		if str(key).begins_with("attack:"):
			attacks += int(pvp["commands"]["fail"][key])
	t.check(attacks > 0, "pvp bots issue attack commands")
	var hits: int = int(pvp["events"]["by_type"].get("hit", 0))
	t.check(hits > 0, "pvp scenario produces hit/damage events")

	t.current = "determinism"
	var again: Dictionary = _small("pvp")
	t.eq(again["commands"]["ok"], pvp["commands"]["ok"], "same seed gives same ok command counts")
	t.eq(again["commands"]["fail"], pvp["commands"]["fail"], "same seed gives same failure counts")

	t.current = "memory slope"
	t.near(LoadGenerator.memory_slope([{"t": 0.0, "bytes": 100}, {"t": 1.0, "bytes": 300}, {"t": 2.0, "bytes": 500}]), 200.0, 0.001, "OLS slope of a line")
	t.eq(LoadGenerator.memory_slope([{"t": 0.0, "bytes": 5}]), 0.0, "single sample has no trend")
