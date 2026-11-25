extends RefCounted
## Regression checks for the frame CPU budget allocator's fairness and safety.

const CpuBudget = preload("res://scripts/shared/cpu_budget.gd")


func run(t) -> void:
	_exercise(t, CpuBudget.new())
	if ClassDB.class_exists("CgameCPUBudget"):
		_exercise(t, ClassDB.instantiate("CgameCPUBudget"))


func _exercise(t, budget: Object) -> void:
	t.current = "priority-weighted frame allocation and proportional minimums"
	budget.register_system("terrain", 2.0, 1.0, 4.0)
	budget.register_system("audio", 1.0, 0.5, 2.0)
	t.eq(budget.system_count(), 2, "both render and audio lanes registered")
	var normal: Dictionary = budget.allocate(3.0)
	t.near(float(normal["terrain"]), 2.0, 0.0001,
		"higher-priority terrain receives its weighted share")
	t.near(float(normal["audio"]), 1.0, 0.0001,
		"lower-priority audio still receives its minimum and fair share")
	var constrained: Dictionary = budget.allocate(0.6)
	t.near(float(constrained["terrain"]), 0.4, 0.0001,
		"terrain minimum scales when the frame is overloaded")
	t.near(float(constrained["audio"]), 0.2, 0.0001,
		"audio minimum scales proportionally to avoid oversubscription")

	t.current = "invalid budget and telemetry are contained"
	for invalid_budget in [-1.0, NAN, INF]:
		var grants: Dictionary = budget.allocate(invalid_budget)
		t.eq(float(grants["terrain"]), 0.0,
			"invalid frame budget never grants terrain work")
		t.eq(float(grants["audio"]), 0.0,
			"invalid frame budget never grants audio work")
	budget.report_usage("terrain", 2.0)
	t.eq(budget.smoothed_usage_ms("terrain"), 2.0,
		"first valid performance measurement initializes the EMA")
	for bad_sample in [NAN, INF, -1.0]:
		budget.report_usage("terrain", bad_sample)
		t.eq(budget.smoothed_usage_ms("terrain"), 2.0,
			"malformed timing cannot poison learned CPU demand")
	budget.smoothing = NAN
	budget.report_usage("terrain", 4.0)
	t.near(budget.smoothed_usage_ms("terrain"), 2.4, 0.0001,
		"invalid smoothing falls back to a bounded EMA factor")
	budget.headroom = NAN
	t.near(budget.demand_ms("terrain"), 2.4, 0.0001,
		"invalid adaptive headroom does not propagate NaN")
	budget.register_system("", 1.0, 1.0, 1.0)
	t.eq(budget.system_count(), 2, "empty lane name is rejected")
	budget.register_system("invalid", NAN, -INF, INF)
	t.eq(budget.demand_ms("invalid"), 0.0,
		"non-finite registration values are safely bounded")
	var recovered: Dictionary = budget.allocate(3.0)
	t.check(is_finite(float(recovered["terrain"])) and is_finite(float(recovered["audio"])),
		"next frame recovers to finite CPU allocations")
	budget.register_system("terrain", 1.0, 0.0, 1.0)
	t.eq(budget.allocation_ms("terrain"), 0.0,
		"reconfiguring a lane invalidates stale allocations")
	budget.unregister_system("invalid")
	t.eq(budget.system_count(), 2, "invalid temporary lane can be removed")
