extends RefCounted
## Game-independent readiness tests for World Partition cell staging.

const Readiness = preload("res://scripts/shared/stream_readiness.gd")


func run(t) -> void:
	t.current = "one navmesh bake per streamed cell"
	var gate := Readiness.new()
	var cell := Vector2i(4, -3)
	gate.begin(cell, 0.0)
	gate.mark(cell, Readiness.Stage.DATA_LOADED)
	gate.mark(cell, Readiness.Stage.PHYSICS_READY)
	var calls: Dictionary = {"total": 0}
	var bake: Callable = func(_unused_cell: Vector2i) -> bool:
		calls["total"] = int(calls["total"]) + 1
		return true
	gate.warmup_navmesh(cell, bake)
	gate.warmup_navmesh(cell, bake)
	t.eq(gate.pending_warmups(), 1,
		"duplicate requests do not queue duplicate expensive navmesh bakes")
	t.eq(gate.process_warmup(10), 1, "one submitted bake consumes one CPU slot")
	t.eq(int(calls["total"]), 1, "navmesh builder ran only once")
	t.check(gate.is_stage_ready(cell, Readiness.Stage.NAVMESH_READY),
		"navmesh stage becomes ready after completed bake")
	gate.warmup_navmesh(cell, bake)
	t.eq(gate.pending_warmups(), 0, "completed cell is never needlessly rebaked")
	t.eq(gate.update(0.2).size(), 0, "no reveal before GPU upload completes")
	gate.mark(cell, Readiness.Stage.GPU_UPLOADED)
	t.eq(gate.update(0.3), [cell], "fully ready cell is revealed exactly once")
	t.eq(gate.update(0.4).size(), 0, "subsequent updates do not replay reveal")

	t.current = "late auto warmup schedules already physical-ready cells"
	var late := Readiness.new()
	var late_cell := Vector2i(12, 8)
	late.mark(late_cell, Readiness.Stage.DATA_LOADED)
	late.mark(late_cell, Readiness.Stage.PHYSICS_READY)
	late.set_auto_warmup(bake)
	t.eq(late.pending_warmups(), 1,
		"enabling auto warmup after physics readiness schedules the missing bake")
	late.set_auto_warmup(bake)
	t.eq(late.pending_warmups(), 1,
		"re-enabling auto warmup does not create duplicates")
	t.eq(late.process_warmup(1), 1,
		"late scheduled navigation work runs within normal CPU budget")
	t.check(late.is_stage_ready(late_cell, Readiness.Stage.NAVMESH_READY),
		"late auto warmup completes the existing cell's navigation")
	late.set_auto_warmup(bake)
	t.eq(late.pending_warmups(), 0,
		"completed late cell cannot be queued again")

	t.current = "unloading during a bake cannot resurrect the stale world cell"
	var unloaded := Readiness.new()
	var old_cell := Vector2i(9, 7)
	unloaded.mark(old_cell, Readiness.Stage.DATA_LOADED)
	unloaded.mark(old_cell, Readiness.Stage.PHYSICS_READY)
	var unloading_bake: Callable = func(_unused_cell: Vector2i) -> bool:
		unloaded.release(old_cell)
		return true
	unloaded.warmup_navmesh(old_cell, unloading_bake)
	t.eq(unloaded.process_warmup(1), 1, "in-flight bake did execute")
	t.check(not unloaded.is_tracked(old_cell), "unloaded cell stays released")
	t.eq(unloaded.pending_warmups(), 0, "old bake leaves no pending work")
	t.eq(unloaded.update(0.5).size(), 0, "stale completion cannot reveal a ghost cell")
