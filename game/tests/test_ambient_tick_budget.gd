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
