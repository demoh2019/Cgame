extends RefCounted
## Headless exact native/fallback parity and live pooled burst queue checks.
const FxPolicy = preload("res://scripts/client/fx_scalability_policy.gd")
const Effects = preload("res://scripts/client/effects.gd")


func run(t) -> void:
	t.current = "category caps protect important combat feedback"
	var d := PackedFloat64Array([1.0, 2.0, 4.0, 3.0, 7.0, 140.0, 141.0])
	var p := PackedByteArray([0, 0, 3, 1, 2, 2, 3])
	var g := PackedByteArray([0, 0, 3, 1, 2, 2, 3])
	for quality in 4:
		var chosen: PackedInt32Array = FxPolicy.select_indices(d, p, g, quality)
		t.check(chosen.size() <= FxPolicy.budget_for(quality), "global quality budget")
		t.eq(chosen[0], 2, "milestone outranks nearby dust")
		t.check(chosen.has(5), "inclusive radius keeps at 140 meters")
		t.check(not chosen.has(6), "effects beyond 140 meters culled")
		var dust_count := 0
		for index in chosen:
			if g[index] == 0:
				dust_count += 1
		t.check(dust_count <= FxPolicy.caps_for(quality)[0], "dust category cap")
	t.eq(FxPolicy.budget_for(-1), FxPolicy.budget_for(0), "low quality clamped")
	t.eq(FxPolicy.budget_for(99), FxPolicy.budget_for(3), "high quality clamped")

	t.current = "reject invalid cosmetic inputs atomically"
	t.eq(FxPolicy.select_indices(PackedFloat64Array([NAN]),
		PackedByteArray([1]), PackedByteArray([1]), 1).size(), 0, "NaN rejected")
	t.eq(FxPolicy.select_indices(PackedFloat64Array([1.0]),
		PackedByteArray([4]), PackedByteArray([1]), 1).size(), 0, "priority rejected")
	t.eq(FxPolicy.select_indices(PackedFloat64Array([1.0]),
		PackedByteArray([1]), PackedByteArray([4]), 1).size(), 0, "category rejected")
	t.eq(FxPolicy.select_indices(PackedFloat64Array([1.0, 2.0]),
		PackedByteArray([1]), PackedByteArray([1]), 1).size(), 0, "mismatch rejected")

	t.current = "native significance selection mirrors game fallback"
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var native = ClassDB.instantiate("SignificanceBudgetPlanner")
		if native != null and native.has_method("select_effects"):
			var rng := RandomNumberGenerator.new()
			rng.seed = 71135
			for quality in 4:
				for sample in 20:
					var distances := PackedFloat64Array()
					var priorities := PackedByteArray()
					var categories := PackedByteArray()
					for i in 64:
						distances.append(rng.randf_range(0.0, 170.0))
						priorities.append(rng.randi_range(0, 3))
						categories.append(rng.randi_range(0, 3))
					t.eq(FxPolicy.select_indices(distances, priorities, categories, quality, native),
						FxPolicy.select_indices(distances, priorities, categories, quality),
						"native parity quality %d sample %d" % [quality, sample])


	t.current = "game graphics tier scales total resident pool, not active effects"
	for quality in 4:
		t.check(FxPolicy.pool_resident_target(quality) > 0,
			"graphics tier %d has a bounded resident target" % quality)
		t.check(FxPolicy.pool_changes_per_frame(quality) <= 2,
			"graphics tier %d never performs more than two operations per frame" % quality)
	t.eq(FxPolicy.pool_resident_target(-1), 2, "Performance target clamps")
	t.eq(FxPolicy.pool_resident_target(99), 12, "Ultra target clamps")
	t.eq(FxPolicy.pool_changes_per_frame(0), 1, "Performance spreads allocations one per frame")
	t.eq(FxPolicy.pool_changes_per_frame(3), 2, "Ultra spreads allocations two per frame")

	t.current = "Albion After enqueues bounded cosmetic nodes"
	var fx := Effects.new()
	fx.burst(Vector3.ZERO, Color.WHITE, 10)
	t.eq(fx.pending_burst_count(), 1, "ordinary burst queues descriptor")
	for i in 255:
		fx.burst(Vector3(float(i), 0.0, 0.0), Color.WHITE, 3, 1.0, 0.3,
			0.1, 7.0, 0.6, 0, 0)
	t.eq(fx.pending_burst_count(), 256, "visual backlog hard bound")
	fx.level_up(Vector3(2.0, 0.0, 0.0))
	t.eq(fx.pending_burst_count(), 256, "higher-priority effect replaces dust")
	var critical := 0
	for effect in fx._pending_bursts:
		if int(effect["priority"]) == 3:
			critical += 1
	t.eq(critical, 1, "milestone retained in saturated visual queue")
	fx.flush_bursts()
	t.eq(fx.pending_burst_count(), 0, "queue emptied once per frame")
	t.eq(fx.last_fx_budget_stats["requested"], 256, "diagnostics record workload")
	t.check(int(fx.last_fx_budget_stats["rendered"]) <= FxPolicy.budget_for(3),
		"no more than Ultra burst budget can instantiate")
	fx.free()
