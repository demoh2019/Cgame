extends RefCounted
## Regression suite for budgeted, client-only ambient simulation updates.

const AmbientTickBudget = preload("res://scripts/client/ambient_tick_budget.gd")


func run(t) -> void:
	var b = AmbientTickBudget.new()
	b.begin_frame(1.0 / 60.0, 0)
	for lane in AmbientTickBudget.LANES:
		t.check(b.consume(lane, 1.0 / 60.0) > 0.0, "Initial quality transition refreshes %s" % lane)
	t.eq(b.last_frame_counts().x, 4, "All lanes refresh immediately on quality changes")
	b.begin_frame(1.0 / 60.0, 0)
	var calls: int = 0
	for lane in AmbientTickBudget.LANES:
		if b.consume(lane, 1.0 / 60.0) > 0.0:
			calls += 1
	t.eq(calls, 0, "Low-tier lanes are not updated every frame")
	var updated: int = 0
	for _i in range(12):
		b.begin_frame(1.0 / 60.0, 0)
		for lane in AmbientTickBudget.LANES:
			if b.consume(lane, 1.0 / 60.0) > 0.0:
				updated += 1
		t.check(b.last_frame_counts().x <= 1, "Low quality honors the frame slot budget")
	t.check(updated >= 4, "No lane is starved by the per-frame budget")
	b.begin_frame(0.05, 0)
	t.check(b.consume("dusk_bats", 0.05, true) > 0.0, "Visibility changes bypass throttling")
	t.eq(b.consume("unknown", 0.1), 0.0, "Unknown channels do not run")
	t.eq(b.consume("dragonflies", INF), 0.0, "Non-finite time deltas are rejected")
	b.begin_frame(1.0 / 60.0, 3)
	t.eq(b.current_budget(), 4, "Ultra allows four ambient lanes per frame")
	var high_updates: int = 0
	for lane in AmbientTickBudget.LANES:
		if b.consume(lane, 1.0 / 60.0) > 0.0:
			high_updates += 1
	t.eq(high_updates, 4, "High-quality transition updates all lanes")
	for _i in range(12):
		b.begin_frame(0.05, 3)
	t.check(b.current_budget() < 4, "Sustained slow frames reduce cosmetic update budget")
	t.check(b.pressure_percent() >= 40.0, "Frame pressure is measurable")
	b.reset()
	t.eq(b.current_budget(), 1, "Reset restores the conservative budget")
	t.eq(b.pressure_percent(), 0.0, "Reset clears stale frame pressure")

	# On the custom Godot fork, verify the native implementation as well.
	# Official editor builds intentionally exercise only the script fallback.
	if ClassDB.class_exists("FrameUpdateBudget"):
		var native: Object = ClassDB.instantiate("FrameUpdateBudget")
		t.check(native != null, "Native frame scheduler can be instantiated")
		if native != null:
			for lane in AmbientTickBudget.LANES:
				t.check(bool(native.call("register_lane", StringName(lane))),
					"Native scheduler registers %s" % lane)
			t.eq(int(native.call("get_lane_count")), 4, "Native registry contains all ambient lanes")
			t.check(not bool(native.call("register_lane", &"dusk_bats")),
				"Native scheduler rejects duplicate lanes")
			t.check(bool(native.call("configure", PackedFloat64Array([12.0, 18.0, 30.0, 60.0]),
				PackedInt32Array([1, 2, 3, 4]))), "Native quality profile is configurable")
			t.check(not bool(native.call("configure", PackedFloat64Array([12.0, -1.0, 30.0, 60.0]),
				PackedInt32Array([1, 2, 3, 4]))), "Native scheduler rejects invalid profiles")
			native.call("begin_frame", 1.0 / 60.0, 0)
			for lane in AmbientTickBudget.LANES:
				t.check(float(native.call("consume", StringName(lane), 1.0 / 60.0)) > 0.0,
					"Native quality transition refreshes %s" % lane)
			native.call("begin_frame", 1.0 / 60.0, 0)
			t.eq(float(native.call("consume", &"dragonflies", 1.0 / 60.0)), 0.0,
				"Native scheduler throttles subsequent frames")
			t.eq(float(native.call("consume", &"missing", 0.1)), 0.0,
				"Native scheduler ignores unknown lanes")
			t.eq(float(native.call("consume", &"dragonflies", INF)), 0.0,
				"Native scheduler guards invalid time deltas")
			t.check(float(native.call("consume", &"dragonflies", 1.0, true)) <= 0.16,
				"Native forced refresh clamps its accumulated time")
			for _i in range(12):
				native.call("begin_frame", 0.05, 3)
			t.check(float(native.call("pressure_percent")) >= 40.0,
				"Native slow-frame pressure is measurable")
			t.check(int(native.call("current_budget")) < 4,
				"Native slow frames reduce presentation slots")
			native.call("reset")
			t.eq(float(native.call("pressure_percent")), 0.0,
				"Native reset clears pressure")

	# Simulate the real game's fixed call order for four seconds at 60 FPS.
	# A one-slot low-quality budget must not starve later ambient systems.
	t.current = "fair ambient slots across fixed-order cosmetic systems"
	var fair := AmbientTickBudget.new()
	var native_fair: Object = null
	if ClassDB.class_exists("FrameUpdateBudget"):
		native_fair = ClassDB.instantiate("FrameUpdateBudget")
		if native_fair != null:
			for lane in AmbientTickBudget.LANES:
				t.check(bool(native_fair.call("register_lane", StringName(lane))),
					"Native fair scheduler registers %s" % lane)
	var counts: Dictionary = {}
	for lane in AmbientTickBudget.LANES:
		counts[lane] = 0
	var call_order: Array[String] = ["dust_devils", "dragonflies", "tumbleweeds", "dusk_bats"]
	for frame in range(241):
		fair.begin_frame(1.0 / 60.0, 0)
		if native_fair != null:
			native_fair.call("begin_frame", 1.0 / 60.0, 0)
		for lane in call_order:
			var interval: float = fair.consume(lane, 1.0 / 60.0)
			if native_fair != null:
				var native_interval: float = float(native_fair.call(
					"consume", StringName(lane), 1.0 / 60.0))
				t.near(native_interval, interval, 0.0000001,
					"Native/script fair slot parity on frame %d for %s" % [frame, lane])
			if frame > 0 and interval > 0.0:
				counts[lane] = int(counts[lane]) + 1
		if frame > 0:
			t.check(fair.last_frame_counts().x <= 1, "Low-tier one-slot budget on frame %d" % frame)
	var smallest: int = 100000
	var largest: int = 0
	for lane in AmbientTickBudget.LANES:
		var updates: int = int(counts[lane])
		t.check(updates >= 40, "%s is not starved" % lane)
		smallest = mini(smallest, updates)
		largest = maxi(largest, updates)
	t.check(largest - smallest <= 2, "Fairness does not depend on registration or call order")

	t.current = "soft CPU time budget and native compatibility"
	var measured := AmbientTickBudget.new()
	t.eq(measured.get_frame_time_budget_us(), 2500, "default microsecond budget")
	t.check(measured.set_frame_time_budget_us(250), "can tune CPU cap")
	t.check(not measured.set_frame_time_budget_us(-1), "negative cap rejected")
	t.check(not measured.record_cost("invalid", 200), "unregistered work rejected")
	measured.begin_frame(0.01, 3)
	for lane in AmbientTickBudget.LANES:
		measured.consume(lane, 0.01)
	t.check(measured.record_cost("dust_devils", 350), "records measured work")
	measured.begin_frame(0.1, 3)
	t.eq(measured.last_frame_cost_us(), 350, "previous frame telemetry")
	t.eq(measured.current_frame_cost_us(), 0, "current frame reset")
	t.check(measured.consume("dust_devils", 0.1) > 0.0, "first lane due")
	measured.record_cost("dust_devils", 300)
	t.eq(measured.consume("dragonflies", 0.1), 0.0, "later work deferred after budget")
	t.check(measured.consume("dragonflies", 0.1, true) > 0.0, "forced work bypasses cap")
	t.check(measured.set_frame_time_budget_us(0), "zero disables CPU cap")
	measured.begin_frame(0.1, 3)
	measured.record_cost("dust_devils", 10000)
	t.check(measured.consume("dragonflies", 0.1) > 0.0, "unlimited profile runs")
	measured.reset()
	t.eq(measured.last_frame_cost_us(), 0, "reset clears cost")

	if ClassDB.class_exists("FrameUpdateBudget"):
		var native_cpu: Object = ClassDB.instantiate("FrameUpdateBudget")
		if native_cpu != null and native_cpu.has_method("record_cost"):
			for lane in AmbientTickBudget.LANES:
				t.check(bool(native_cpu.call("register_lane", StringName(lane))),
					"native budget registers %s" % lane)
			t.check(bool(native_cpu.call("set_frame_time_budget_us", 250)),
				"native CPU cap configurable")
			native_cpu.call("begin_frame", 0.01, 3)
			for lane in AmbientTickBudget.LANES:
				native_cpu.call("consume", StringName(lane), 0.01)
			native_cpu.call("record_cost", &"dust_devils", 350)
			native_cpu.call("begin_frame", 0.1, 3)
			t.eq(int(native_cpu.call("last_frame_cost_us")), 350, "native telemetry")
			t.check(float(native_cpu.call("consume", &"dust_devils", 0.1)) > 0.0,
				"native lane due")
			native_cpu.call("record_cost", &"dust_devils", 300)
			t.eq(float(native_cpu.call("consume", &"dragonflies", 0.1)), 0.0,
				"native CPU budget prevents extra work")
			t.check(float(native_cpu.call("consume", &"dragonflies", 0.1, true)) > 0.0,
				"native forced work bypasses soft limit")

	t.current = "outdoor cosmetic lanes pause in caves and resume without stale backlog"
	var suspended := AmbientTickBudget.new()
	suspended.begin_frame(0.01, 3)
	for lane in AmbientTickBudget.LANES:
		suspended.consume(lane, 0.01)
	for lane in AmbientTickBudget.LANES:
		t.check(suspended.set_lane_enabled(lane, false), "suspend %s" % lane)
	t.eq(suspended.get_enabled_lane_count(), 0, "no outdoor lanes run underground")
	suspended.begin_frame(0.1, 3)
	t.eq(suspended.current_budget(), 0, "underground lanes reserve no CPU slots")
	for lane in AmbientTickBudget.LANES:
		t.eq(suspended.consume(lane, 0.1), 0.0, "suppressed %s stays stopped" % lane)
	t.check(suspended.consume("dust_devils", 0.1, true) > 0.0,
		"cave transition can still clear existing dust effects")
	suspended.begin_frame(0.1, 3)
	t.eq(suspended.consume("dust_devils", 0.1), 0.0, "no repeat update while disabled")
	t.check(not suspended.set_lane_enabled("missing", false), "unknown lanes rejected")
	t.check(suspended.set_lane_enabled("dragonflies", true), "outside scene reenables dragonflies")
	t.check(suspended.set_lane_enabled("dragonflies", true), "idempotent enable keeps pending refresh")
	t.eq(suspended.get_enabled_lane_count(), 1, "only one outdoor lane is active")
	suspended.begin_frame(0.001, 3)
	t.eq(suspended.current_budget(), 1, "available slots follow enabled lanes")
	var resumed_delta: float = suspended.consume("dragonflies", 0.001)
	t.near(resumed_delta, 0.001, 0.0000001, "returning to daylight refreshes immediately")
	t.eq(suspended.consume("dragonflies", 0.001), 0.0,
		"single-use resume does not grant another update")
	suspended.reset()
	t.check(not suspended.is_lane_enabled("dusk_bats"), "reset preserves cave suspension")

	if ClassDB.class_exists("FrameUpdateBudget"):
		var resumed_native: Object = ClassDB.instantiate("FrameUpdateBudget")
		if resumed_native != null and resumed_native.has_method("set_lane_enabled"):
			for lane in AmbientTickBudget.LANES:
				resumed_native.call("register_lane", StringName(lane))
			resumed_native.call("begin_frame", 0.01, 3)
			for lane in AmbientTickBudget.LANES:
				resumed_native.call("consume", StringName(lane), 0.01)
			for lane in AmbientTickBudget.LANES:
				t.check(bool(resumed_native.call("set_lane_enabled", StringName(lane), false)),
					"native suspension for %s" % lane)
			resumed_native.call("begin_frame", 0.1, 3)
			t.eq(int(resumed_native.call("current_budget")), 0, "native no-slot cave parity")
			for lane in AmbientTickBudget.LANES:
				t.eq(float(resumed_native.call("consume", StringName(lane), 0.1)), 0.0,
					"native %s remains suspended" % lane)
			t.check(float(resumed_native.call("consume", &"dust_devils", 0.1, true)) > 0.0,
				"native forced cave cleanup")
			resumed_native.call("begin_frame", 0.1, 3)
			t.eq(float(resumed_native.call("consume", &"dust_devils", 0.1)), 0.0,
				"native suspended dust stays stopped")
			resumed_native.call("set_lane_enabled", &"dragonflies", true)
			resumed_native.call("set_lane_enabled", &"dragonflies", true)
			t.eq(int(resumed_native.call("get_enabled_lane_count")), 1,
				"native active lane count matches GDScript")
			resumed_native.call("begin_frame", 0.001, 3)
			t.near(float(resumed_native.call("consume", &"dragonflies", 0.001)),
				resumed_delta, 0.0000001, "native and script resume parity")
			t.eq(float(resumed_native.call("consume", &"dragonflies", 0.001)), 0.0,
				"native immediate resume is single-use")

	t.current = "scene-aware importance with learned CPU costs"
	var daylight_weights: Dictionary = AmbientTickBudget.suggested_importance(0.8, false, false)
	var night_weights: Dictionary = AmbientTickBudget.suggested_importance(0.1, false, false)
	var storm_weights: Dictionary = AmbientTickBudget.suggested_importance(0.8, true, false)
	var cave_weights: Dictionary = AmbientTickBudget.suggested_importance(0.8, false, true)
	t.check(float(daylight_weights["dragonflies"]) > float(daylight_weights["dusk_bats"]),
		"dragonflies take daytime significance")
	t.check(float(night_weights["dusk_bats"]) > float(night_weights["dragonflies"]),
		"dusk bats take nighttime significance")
	t.check(float(storm_weights["dust_devils"]) > float(storm_weights["dragonflies"]),
		"storm-weighted landscape changes priority")
	for lane in AmbientTickBudget.LANES:
		t.eq(float(cave_weights[lane]), 0.25, "underground %s is low significance" % lane)

	var weighted := AmbientTickBudget.new()
	t.check(weighted.set_frame_time_budget_us(500), "significance scheduler sets CPU budget")
	t.check(not weighted.set_lane_importance("dust_devils", 0.0), "invalid importance rejected")
	t.check(not weighted.set_lane_importance("dust_devils", NAN), "NaN importance rejected")
	t.check(not weighted.set_lane_importance("missing", 1.0), "unknown lane rejected")
	t.check(weighted.set_lane_importance("dust_devils", 0.25), "heavy effects deprioritized")
	t.check(weighted.set_lane_importance("dragonflies", 4.0), "visible effects prioritized")
	t.eq(weighted.get_lane_importance("dragonflies"), 4.0, "importance can be inspected")
	weighted.begin_frame(0.01, 0)
	for lane in AmbientTickBudget.LANES:
		weighted.consume(lane, 0.01)
	t.check(weighted.record_cost("dust_devils", 1500), "heavy effect's cost measured")
	t.check(weighted.record_cost("dragonflies", 100), "cheap effect's cost measured")
	t.eq(weighted.get_lane_estimated_cost_us("dust_devils"), 1500, "EMA starts with first sample")
	t.check(weighted.record_cost("dust_devils", 500), "next heavy sample is accepted")
	t.eq(weighted.get_lane_estimated_cost_us("dust_devils"), 1250, "estimated cost uses EMA")
	t.check(weighted.set_lane_importance("tumbleweeds", 0.25), "third lane low priority")
	t.check(weighted.set_lane_importance("dusk_bats", 0.25), "fourth lane low priority")

	var native_weighted: Object = null
	if ClassDB.class_exists("FrameUpdateBudget"):
		var candidate: Object = ClassDB.instantiate("FrameUpdateBudget")
		if candidate != null and candidate.has_method("set_lane_importance") \
				and candidate.has_method("get_reserved_estimated_cost_us"):
			native_weighted = candidate
			for lane in AmbientTickBudget.LANES:
				t.check(bool(native_weighted.call("register_lane", StringName(lane))),
					"native importance lane %s registered" % lane)
				t.check(bool(native_weighted.call("set_lane_importance",
					StringName(lane), weighted.get_lane_importance(lane))),
					"native importance weight for %s accepted" % lane)
			native_weighted.call("set_frame_time_budget_us", 500)
			native_weighted.call("begin_frame", 0.01, 0)
			for lane in AmbientTickBudget.LANES:
				native_weighted.call("consume", StringName(lane), 0.01)
			native_weighted.call("record_cost", &"dust_devils", 1500)
			native_weighted.call("record_cost", &"dragonflies", 100)
			native_weighted.call("record_cost", &"dust_devils", 500)
			t.eq(int(native_weighted.call("get_lane_estimated_cost_us", &"dust_devils")),
				1250, "native learned cost matches GDScript")

	weighted.begin_frame(0.1, 0)
	t.eq(weighted.get_reserved_estimated_cost_us(), 100,
		"forecaster reserves affordable channel instead of expensive one")
	if native_weighted != null:
		native_weighted.call("begin_frame", 0.1, 0)
		t.eq(int(native_weighted.call("get_reserved_estimated_cost_us")), 100,
			"native predicted reservation matches GDScript")
	var heavy_count: int = 0
	for frame in range(100):
		if frame > 0:
			weighted.begin_frame(0.1, 0)
			if native_weighted != null:
				native_weighted.call("begin_frame", 0.1, 0)
		for lane in AmbientTickBudget.LANES:
			var result: float = weighted.consume(lane, 0.1)
			if native_weighted != null:
				var native_result: float = float(native_weighted.call(
					"consume", StringName(lane), 0.1))
				t.near(native_result, result, 0.0000001,
					"native/script priority parity on frame %d for %s" % [frame, lane])
			if result > 0.0:
				var elapsed_us: int = 1500 if lane == "dust_devils" else 100
				weighted.record_cost(lane, elapsed_us)
				if native_weighted != null:
					native_weighted.call("record_cost", StringName(lane), elapsed_us)
				if lane == "dust_devils":
					heavy_count += 1
	t.check(heavy_count >= 1, "old expensive lane is eventually scheduled")

	t.current = "per-lane rate and cost-significance parity"
	t.near(AmbientTickBudget.rate_scale_for_importance(0.25), 0.75, 0.000001,
		"low significance limits cosmetic update frequency")
	t.near(AmbientTickBudget.rate_scale_for_importance(1.0), 1.0, 0.000001,
		"default importance preserves baseline rate")
	t.near(AmbientTickBudget.rate_scale_for_importance(4.0), 1.5, 0.000001,
		"high significance increases cosmetic frequency")
	t.eq(AmbientTickBudget.rate_scale_for_importance(INF), 1.0,
		"nonfinite importance cannot corrupt a lane's rate")
	var rate_script := AmbientTickBudget.new()
	t.eq(rate_script.get_lane_rate_scale("dragonflies"), 1.0, "default lane frequency")
	t.check(rate_script.set_lane_rate_scale("dragonflies", 1.5), "valid rate accepted")
	t.check(not rate_script.set_lane_rate_scale("dragonflies", 0.5), "out-of-range rate rejected")
	t.check(not rate_script.set_lane_rate_scale("dragonflies", NAN), "NaN rate rejected")
	t.check(not rate_script.set_lane_rate_scale("missing", 1.0), "unknown lane rejected")
	t.eq(rate_script.get_lane_rate_scale("dragonflies"), 1.5, "rejected update keeps prior value")
	t.eq(rate_script.get_lane_rate_scale("missing"), -1.0, "unknown lane sentinel")
	rate_script.reset()
	t.eq(rate_script.get_lane_rate_scale("dragonflies"), 1.5, "rate configuration survives reset")

	var rate_native: Object = null
	if ClassDB.class_exists("FrameUpdateBudget"):
		var candidate_rates: Object = ClassDB.instantiate("FrameUpdateBudget")
		if candidate_rates != null and candidate_rates.has_method("set_lane_rate_scale"):
			rate_native = candidate_rates
			for lane in AmbientTickBudget.LANES:
				t.check(bool(rate_native.call("register_lane", StringName(lane))),
					"native rate-aware lane %s registered" % lane)
	var rate_weights: Dictionary = AmbientTickBudget.suggested_importance(0.8, false, false)
	var rate_counts: Dictionary = {}
	for lane in AmbientTickBudget.LANES:
		var importance: float = float(rate_weights[lane])
		var multiplier: float = AmbientTickBudget.rate_scale_for_importance(importance)
		rate_counts[lane] = 0
		t.check(rate_script.set_lane_importance(lane, importance), "script importance %s" % lane)
		t.check(rate_script.set_lane_rate_scale(lane, multiplier), "script rate %s" % lane)
		if rate_native != null:
			t.check(bool(rate_native.call("set_lane_importance", StringName(lane), importance)),
				"native importance %s" % lane)
			t.check(bool(rate_native.call("set_lane_rate_scale", StringName(lane), multiplier)),
				"native rate %s" % lane)
	var rate_call_order: Array[String] = ["dust_devils", "dragonflies", "tumbleweeds", "dusk_bats"]
	for frame in range(241):
		rate_script.begin_frame(1.0 / 60.0, 1)
		if rate_native != null:
			rate_native.call("begin_frame", 1.0 / 60.0, 1)
		for lane in rate_call_order:
			var scripted_delta: float = rate_script.consume(lane, 1.0 / 60.0)
			if rate_native != null:
				t.near(float(rate_native.call("consume", StringName(lane), 1.0 / 60.0)),
					scripted_delta, 0.0000001,
					"native/script significance and rate parity frame %d lane %s" % [frame, lane])
			if frame > 0 and scripted_delta > 0.0:
				rate_counts[lane] = int(rate_counts[lane]) + 1
		if frame > 0:
			t.check(rate_script.last_frame_counts().x <= 2, "quality 1 never exceeds two slots")
	t.check(int(rate_counts["dragonflies"]) > int(rate_counts["dusk_bats"]) + 5,
		"sunlit insects update more frequently than daytime bats")
	for lane in AmbientTickBudget.LANES:
		t.check(int(rate_counts[lane]) >= 20, "%s still gets regular updates" % lane)


	t.current = "per-lane completed-frame CPU profiler parity"
	var samples := AmbientTickBudget.new()
	var native_samples: Object = null
	if ClassDB.class_exists("FrameUpdateBudget"):
		var candidate_samples: Object = ClassDB.instantiate("FrameUpdateBudget")
		if candidate_samples != null and candidate_samples.has_method("get_lane_last_frame_cost_us"):
			native_samples = candidate_samples
			for lane in AmbientTickBudget.LANES:
				t.check(bool(native_samples.call("register_lane", StringName(lane))),
					"native per-lane profiler registers %s" % lane)
	samples.begin_frame(0.01, 3)
	if native_samples != null:
		native_samples.call("begin_frame", 0.01, 3)
	for lane in AmbientTickBudget.LANES:
		samples.consume(lane, 0.01)
		if native_samples != null:
			native_samples.call("consume", StringName(lane), 0.01)
	for report in [["dust_devils", 120], ["dust_devils", 45], ["dragonflies", 70]]:
		t.check(samples.record_cost(str(report[0]), int(report[1])), "script CPU sample accepted")
		if native_samples != null:
			t.check(bool(native_samples.call("record_cost", StringName(str(report[0])), int(report[1]))),
				"native CPU sample accepted")
	t.eq(samples.get_lane_last_frame_cost_us("dust_devils"), 0,
		"partial current-frame costs are hidden")
	t.eq(samples.get_lane_last_frame_cost_us("missing"), -1, "unknown lane reports -1")
	samples.begin_frame(0.01, 3)
	if native_samples != null:
		native_samples.call("begin_frame", 0.01, 3)
	for lane in AmbientTickBudget.LANES:
		var lane_cost: int = samples.get_lane_last_frame_cost_us(lane)
		t.eq(lane_cost, 165 if lane == "dust_devils" else (70 if lane == "dragonflies" else 0),
			"correct completed CPU cost for %s" % lane)
		if native_samples != null:
			t.eq(int(native_samples.call("get_lane_last_frame_cost_us", StringName(lane))), lane_cost,
				"native/script per-lane CPU parity for %s" % lane)
	samples.begin_frame(0.01, 3)
	if native_samples != null:
		native_samples.call("begin_frame", 0.01, 3)
	for lane in AmbientTickBudget.LANES:
		t.eq(samples.get_lane_last_frame_cost_us(lane), 0, "idle CPU sample clears for %s" % lane)
		if native_samples != null:
			t.eq(int(native_samples.call("get_lane_last_frame_cost_us", StringName(lane))), 0,
				"native idle sample clears for %s" % lane)
	samples.record_cost("dust_devils", 200)
	samples.reset()
	t.eq(samples.get_lane_last_frame_cost_us("dust_devils"), 0, "reset clears lane telemetry")
	if native_samples != null:
		native_samples.call("record_cost", &"dust_devils", 200)
		native_samples.call("reset")
		t.eq(int(native_samples.call("get_lane_last_frame_cost_us", &"dust_devils")), 0,
			"native reset clears lane telemetry")

	t.current = "significance-aware deferred-frame deadlines"
	t.eq(AmbientTickBudget.deadline_frames_for_importance(3.0), 8,
		"visible effects receive a short soft deadline")
	t.eq(AmbientTickBudget.deadline_frames_for_importance(0.25), 0,
		"irrelevant ambience has no deadline")
	t.eq(AmbientTickBudget.deadline_frames_for_importance(NAN), 0,
		"nonfinite significance never enables deadline priority")
	var deadline_script := AmbientTickBudget.new()
	t.eq(deadline_script.get_lane_max_deferred_frames("dust_devils"), 0,
		"legacy scheduling has deadlines disabled")
	t.eq(deadline_script.get_lane_max_deferred_frames("missing"), -1,
		"unregistered deadline query returns -1")
	t.check(not deadline_script.set_lane_max_deferred_frames("missing", 2),
		"deadline setter rejects unknown lane")
	t.check(not deadline_script.set_lane_max_deferred_frames("dust_devils", 121),
		"deadline setter rejects invalid frame count")
	t.check(deadline_script.set_lane_max_deferred_frames("dust_devils", 2),
		"heavy lane can opt into a two-frame deadline")
	deadline_script.set_lane_importance("dust_devils", 0.25)
	deadline_script.set_lane_importance("dragonflies", 4.0)
	deadline_script.set_frame_time_budget_us(200)
	var deadline_native: Object = null
	if ClassDB.class_exists("FrameUpdateBudget"):
		var candidate: Object = ClassDB.instantiate("FrameUpdateBudget")
		if candidate != null and candidate.has_method("set_lane_max_deferred_frames"):
			deadline_native = candidate
			for lane in AmbientTickBudget.LANES:
				t.check(bool(deadline_native.call("register_lane", StringName(lane))),
					"native deadline lane registered")
			deadline_native.call("set_lane_max_deferred_frames", &"dust_devils", 2)
			deadline_native.call("set_lane_importance", &"dust_devils", 0.25)
			deadline_native.call("set_lane_importance", &"dragonflies", 4.0)
			deadline_native.call("set_frame_time_budget_us", 200)
	var heavy_grants: int = 0
	for frame in 5:
		deadline_script.begin_frame(0.1, 0)
		if deadline_native != null:
			deadline_native.call("begin_frame", 0.1, 0)
		for lane in AmbientTickBudget.LANES:
			var granted: float = deadline_script.consume(lane, 0.1)
			if deadline_native != null:
				t.near(float(deadline_native.call("consume", StringName(lane), 0.1)),
					granted, 0.0000001,
					"native/script deadline grant parity frame %d lane %s" % [frame, lane])
			if granted > 0.0:
				var work_us: int = 1500 if lane == "dust_devils" else 80
				deadline_script.record_cost(lane, work_us)
				if deadline_native != null:
					deadline_native.call("record_cost", StringName(lane), work_us)
				if frame > 0 and lane == "dust_devils":
					heavy_grants += 1
		if deadline_native != null:
			t.eq(int(deadline_native.call("get_deadline_overdue_lane_count")),
				deadline_script.get_deadline_overdue_lane_count(),
				"native/script overdue deadline telemetry matches")
		if frame > 0:
			t.check(deadline_script.last_frame_counts().x <= 1,
				"deadline priority never exceeds single-slot frame budget")
	t.check(heavy_grants >= 1,
		"costly deadline lane runs without waiting for legacy age-48 escape")
	deadline_script.reset()
	t.eq(deadline_script.get_lane_max_deferred_frames("dust_devils"), 2,
		"deadline configuration survives reset")
	t.eq(deadline_script.get_deadline_overdue_lane_count(), 0,
		"reset clears overdue pressure")
	var online_source := FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(online_source.contains("Albion/AmbientDeadlineOverdue"),
		"Albion profiler exposes deadline pressure")
	t.check(online_source.contains("deadline_frames_for_importance"),
		"real gameplay adjusts deadlines for scene significance")

