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
