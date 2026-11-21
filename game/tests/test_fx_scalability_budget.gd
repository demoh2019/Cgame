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


	t.current = "on-screen effects win slots only inside their priority tier"
	var fd := PackedFloat64Array([5.0, 8.0, 1.0, 2.0, 141.0])
	var fp := PackedByteArray([1, 1, 2, 1, 3])
	var fg := PackedByteArray([0, 0, 1, 0, 1])
	var fv := PackedByteArray([0, 1, 0, 1, 1])
	var expected := PackedInt32Array([2, 3, 1, 0])
	t.eq(FxPolicy.select_visible_indices(fd, fp, fg, fv, 3), expected,
		"critical off-screen effect precedes less important on-screen effects")
	t.eq(FxPolicy.select_visible_indices(fd, fp, fg,
		PackedByteArray([0, 2, 0, 1, 1]), 3).size(), 0, "bad visibility fails closed")
	t.eq(FxPolicy.select_visible_indices(fd, fp, fg,
		PackedByteArray([0]), 3).size(), 0, "visibility length fails closed")
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var visible_native = ClassDB.instantiate("SignificanceBudgetPlanner")
		if visible_native != null and visible_native.has_method("select_effects_visible"):
			t.eq(FxPolicy.select_visible_indices(fd, fp, fg, fv, 3, visible_native),
				expected, "native on-screen admission matches the fallback")
			var rng_visible := RandomNumberGenerator.new()
			rng_visible.seed = 88421
			for quality in 4:
				for sample in 12:
					var vd := PackedFloat64Array()
					var vp := PackedByteArray()
					var vg := PackedByteArray()
					var vv := PackedByteArray()
					for i in 48:
						vd.append(rng_visible.randf_range(0.0, 155.0))
						vp.append(rng_visible.randi_range(0, 3))
						vg.append(rng_visible.randi_range(0, 3))
						vv.append(rng_visible.randi_range(0, 1))
					t.eq(FxPolicy.select_visible_indices(vd, vp, vg, vv, quality, visible_native),
						FxPolicy.select_visible_indices(vd, vp, vg, vv, quality),
						"frustum native parity quality %d sample %d" % [quality, sample])


	t.current = "Niagara category ranges cull distant dust and keep milestones"
	var rd := PackedFloat64Array([40.0, 40.01, 80.0, 80.01, 120.0, 120.01, 140.0, 140.01])
	var rp := PackedByteArray([0, 0, 1, 1, 2, 2, 3, 3])
	var rg := PackedByteArray([0, 0, 1, 1, 2, 2, 3, 3])
	var rv := PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1])
	t.eq(FxPolicy.select_visible_ranged_indices(rd, rp, rg, rv, 3),
		PackedInt32Array([6, 4, 2, 0]), "inclusive Ultra distance thresholds")
	t.eq(FxPolicy.select_visible_ranged_indices(rd, rp, rg, rv, 0),
		PackedInt32Array([6]), "Performance cuts tiny distant effects, not milestones")
	t.eq(FxPolicy.ranges_for(-1), FxPolicy.ranges_for(0), "low quality range clamps")
	t.eq(FxPolicy.ranges_for(99), FxPolicy.ranges_for(3), "high quality range clamps")
	t.eq(FxPolicy.select_visible_ranged_indices(PackedFloat64Array([1.0]),
		PackedByteArray([1]), PackedByteArray([0]), PackedByteArray([2]), 3).size(),
		0, "bad visibility rejected atomically")
	t.eq(FxPolicy.select_visible_ranged_indices(PackedFloat64Array([NAN]),
		PackedByteArray([1]), PackedByteArray([0]), PackedByteArray([1]), 3).size(),
		0, "invalid distance rejected atomically")
	t.eq(FxPolicy.select_visible_ranged_indices(PackedFloat64Array([1.0, 2.0]),
		PackedByteArray([1]), PackedByteArray([0]), PackedByteArray([1]), 3).size(),
		0, "mismatched arrays rejected atomically")
	t.eq(FxPolicy.select_visible_ranged_indices(PackedFloat64Array([10.0, 12.0]),
		PackedByteArray([0, 3]), PackedByteArray([0, 3]),
		PackedByteArray([1, 0]), 3), PackedInt32Array([1, 0]),
		"critical off-screen effect outranks visible dust")
	for quality in 4:
		var limits: PackedFloat64Array = FxPolicy.ranges_for(quality)
		t.check(limits.size() == 4 and limits[0] < limits[1] and limits[1] < limits[2]
			and limits[2] <= limits[3] and limits[3] <= FxPolicy.MAX_DISTANCE,
			"bounded tiered cosmetic ranges")

	t.current = "per-category range admission native and fallback parity"
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var ranged_native = ClassDB.instantiate("SignificanceBudgetPlanner")
		if ranged_native != null and ranged_native.has_method("select_effects_visible_ranged"):
			t.eq(FxPolicy.select_visible_ranged_indices(rd, rp, rg, rv, 3, ranged_native),
				PackedInt32Array([6, 4, 2, 0]), "native range boundaries agree")
			var rng_ranged := RandomNumberGenerator.new()
			rng_ranged.seed = 945102
			for quality in 4:
				for sample in 20:
					var sd := PackedFloat64Array()
					var sp := PackedByteArray()
					var sg := PackedByteArray()
					var sv := PackedByteArray()
					for i in 96:
						sd.append(rng_ranged.randf_range(0.0, 160.0))
						sp.append(rng_ranged.randi_range(0, 3))
						sg.append(rng_ranged.randi_range(0, 3))
						sv.append(rng_ranged.randi_range(0, 1))
					t.eq(FxPolicy.select_visible_ranged_indices(sd, sp, sg, sv, quality, ranged_native),
						FxPolicy.select_visible_ranged_indices(sd, sp, sg, sv, quality),
						"native ranged parity quality %d sample %d" % [quality, sample])

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


	t.current = "Niagara-style soft category slots protect hit particles from combat VFX storms"
	var fair_d := PackedFloat64Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	var fair_p := PackedByteArray([3, 3, 3, 3, 2, 2, 2, 2, 2, 1])
	var fair_g := PackedByteArray([3, 3, 3, 3, 2, 2, 2, 2, 2, 1])
	var fair_v := PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	t.eq(FxPolicy.select_visible_ranged_indices(fair_d, fair_p, fair_g,
		fair_v, 0), PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7]),
		"old strict-significance policy can starve ordinary hit effects")
	var fair_selected: PackedInt32Array = FxPolicy.select_visible_fair_indices(
		fair_d, fair_p, fair_g, fair_v, 0)
	t.eq(fair_selected, PackedInt32Array([0, 1, 2, 3, 4, 9, 5, 6]),
		"priority-3 milestones always win, followed by protected hit/combat quotas")
	t.eq(fair_selected.size(), FxPolicy.budget_for(0),
		"minimum reservations never allocate extra particle instances")
	t.eq(FxPolicy.minimums_for(0), PackedInt32Array([0, 1, 1, 0]),
		"Performance reserves only two cheap combat-category slots")
	t.eq(FxPolicy.minimums_for(3), PackedInt32Array([0, 2, 3, 0]),
		"Ultra can retain more visible combat feedback")
	var emergency_p := PackedByteArray([3, 3, 3, 3, 3, 3, 3, 3, 3, 1])
	var emergent: PackedInt32Array = FxPolicy.select_visible_fair_indices(
		fair_d, emergency_p, fair_g, fair_v, 0)
	t.eq(emergent, PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7]),
		"priority-3 emergency VFX preempt soft reservations when the frame is full")

	t.current = "fair VFX planner preserves hard ranges and rejects invalid arrays"
	t.eq(FxPolicy.select_visible_fair_indices(
		PackedFloat64Array([18.0, 18.01, 20.0, 30.0]),
		PackedByteArray([0, 0, 2, 2]),
		PackedByteArray([0, 0, 1, 2]), PackedByteArray([1, 1, 1, 1]), 0),
		PackedInt32Array([2, 3, 0]), "Performance range culls dust past 18m")
	t.eq(FxPolicy.select_visible_fair_indices(PackedFloat64Array([NAN]),
		PackedByteArray([1]), PackedByteArray([1]),
		PackedByteArray([1]), 0).size(), 0, "NaN effects rejected")
	t.eq(FxPolicy.select_visible_fair_indices(PackedFloat64Array([1.0]),
		PackedByteArray([4]), PackedByteArray([1]),
		PackedByteArray([1]), 0).size(), 0, "invalid priority rejected")
	t.eq(FxPolicy.select_visible_fair_indices(PackedFloat64Array([1.0]),
		PackedByteArray([1]), PackedByteArray([1]),
		PackedByteArray([2]), 0).size(), 0, "invalid visibility rejected")
	t.eq(FxPolicy.select_visible_fair_indices(PackedFloat64Array([1.0, 2.0]),
		PackedByteArray([1]), PackedByteArray([1]),
		PackedByteArray([1]), 0).size(), 0, "mismatched batch rejected")

	t.current = "native soft VFX quotas remain parity-safe with stock Godot"
	if ClassDB.class_exists("SignificanceBudgetPlanner"):
		var fair_native: Object = ClassDB.instantiate("SignificanceBudgetPlanner")
		if fair_native != null and fair_native.has_method("select_effects_visible_fair"):
			t.eq(FxPolicy.select_visible_fair_indices(
				fair_d, fair_p, fair_g, fair_v, 0, fair_native), fair_selected,
				"native engine matches soft reservation fallback on known case")
			var fair_rng := RandomNumberGenerator.new()
			fair_rng.seed = 410266
			for quality in 4:
				for trial in 18:
					var fd := PackedFloat64Array()
					var fp := PackedByteArray()
					var fg := PackedByteArray()
					var fv := PackedByteArray()
					for index in 96:
						fd.append(fair_rng.randf_range(0.0, 170.0))
						fp.append(fair_rng.randi_range(0, 3))
						fg.append(fair_rng.randi_range(0, 3))
						fv.append(fair_rng.randi_range(0, 1))
					t.eq(FxPolicy.select_visible_fair_indices(fd, fp, fg, fv,
						quality, fair_native),
						FxPolicy.select_visible_fair_indices(fd, fp, fg, fv, quality),
						"native/script fair VFX selection parity q%d sample%d" % [quality, trial])
	else:
		t.eq(FxPolicy.select_visible_fair_indices(fair_d, fair_p, fair_g,
			fair_v, 0), fair_selected, "older native builds use portable VFX planner")
	var real_fx_source: String = FileAccess.get_file_as_string("res://scripts/client/effects.gd")
	t.check(real_fx_source.contains("FxPolicy.select_visible_fair_indices("),
		"actual Albion After burst queue enables category diversity every frame")
