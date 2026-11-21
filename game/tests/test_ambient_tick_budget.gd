extends RefCounted
## Regression suite for budgeted, client-only ambient simulation updates.

const AmbientTickBudget = preload("res://scripts/client/ambient_tick_budget.gd")
const AmbientRateProfile = preload("res://scripts/client/ambient_rate_profile.gd")


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

	t.current = "significance profiles follow world conditions"
	var sun_flags: int = AmbientRateProfile.active_flags(
		2, "plains", Vector2(0.5, 0.0), 0.8, 0.0, false)
	t.eq(sun_flags, 7, "daylight, dry wind and plains favor visible ambient effects")
	var night_flags: int = AmbientRateProfile.active_flags(
		2, "plains", Vector2(0.5, 0.0), 0.2, 0.0, false)
	t.eq(night_flags, 12, "night favors bats and rolling tumbleweeds")
	t.eq(AmbientRateProfile.active_flags(
		2, "plains", Vector2(0.5, 0.0), 0.8, 0.5, false), 4,
		"storm suppresses dragonflies and dust devils")
	t.eq(AmbientRateProfile.active_flags(
		2, "plains", Vector2(0.5, 0.0), 0.8, 0.0, true), 0,
		"no ambient effects are significant underground")
	t.eq(AmbientRateProfile.active_flags(
		0, "plains", Vector2(0.5, 0.0), 0.8, 0.0, false), 0,
		"Performance tier does not prioritize disabled effects")
	var sun_rates: Dictionary = AmbientRateProfile.scales_for_flags(sun_flags)
	t.eq(float(sun_rates["dragonflies"]), 1.5, "visible day insect priority")
	t.eq(float(sun_rates["dusk_bats"]), 0.75, "hidden day bat priority")
	t.eq(AmbientRateProfile.scales_for_flags(night_flags)["dusk_bats"], 1.5,
		"night bat update priority")

	t.current = "per-lane rate validation and native fallback parity"
	var script_rates := AmbientTickBudget.new()
	t.eq(script_rates.get_lane_rate_scale("dust_devils"), 1.0, "default scale")
	t.check(script_rates.set_lane_rate_scale("dust_devils", 1.5), "visible lane scale accepted")
	t.check(script_rates.set_lane_rate_scale("dusk_bats", 0.75), "hidden lane scale accepted")
	t.check(not script_rates.set_lane_rate_scale("dusk_bats", 0.5), "low scale rejected")
	t.check(not script_rates.set_lane_rate_scale("dusk_bats", INF), "nonfinite scale rejected")
	t.check(not script_rates.set_lane_rate_scale("unknown", 1.5), "unknown lane rejected")
	t.eq(script_rates.get_lane_rate_scale("unknown"), -1.0, "unknown lane sentinel")
	t.eq(script_rates.get_lane_rate_scale("dusk_bats"), 0.75, "invalid mutation is atomic")
	script_rates.reset()
	t.eq(script_rates.get_lane_rate_scale("dust_devils"), 1.5, "reset retains lane profile")

	var scripted := AmbientTickBudget.new()
	var native_rates: Object = null
	if ClassDB.class_exists("FrameUpdateBudget"):
		var candidate: Object = ClassDB.instantiate("FrameUpdateBudget")
		if candidate != null and candidate.has_method("set_lane_rate_scale"):
			native_rates = candidate
			for lane in AmbientTickBudget.LANES:
				t.check(bool(native_rates.call("register_lane", StringName(lane))),
					"Native rate-aware scheduler registers %s" % lane)
	var seen: Dictionary = {}
	for lane in AmbientTickBudget.LANES:
		seen[lane] = 0
		var scale: float = float(sun_rates[lane])
		t.check(scripted.set_lane_rate_scale(lane, scale), "Script lane profile accepts %s" % lane)
		if native_rates != null:
			t.check(bool(native_rates.call("set_lane_rate_scale", StringName(lane), scale)),
				"Native lane profile accepts %s" % lane)
	for frame in range(241):
		scripted.begin_frame(1.0 / 60.0, 1)
		if native_rates != null:
			native_rates.call("begin_frame", 1.0 / 60.0, 1)
		for lane in call_order:
			var elapsed: float = scripted.consume(lane, 1.0 / 60.0)
			if native_rates != null:
				t.near(float(native_rates.call("consume", StringName(lane), 1.0 / 60.0)),
					elapsed, 0.0000001, "Native/script significance parity %s frame %d" % [lane, frame])
			if frame > 0 and elapsed > 0.0:
				seen[lane] = int(seen[lane]) + 1
		if frame > 0:
			t.check(scripted.last_frame_counts().x <= 2, "Low-mid tier CPU slot cap")
	t.check(int(seen["dragonflies"]) > int(seen["dusk_bats"]) + 8,
		"Relevant dragonflies receive more updates than hidden bats")
	for lane in AmbientTickBudget.LANES:
		t.check(int(seen[lane]) >= 20, "%s is never starved by significance" % lane)
