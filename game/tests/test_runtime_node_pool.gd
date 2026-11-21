extends RefCounted
## Synchronous regression checks for generic pooling and Albion After VFX.

const PoolScript = preload("res://addons/runtime_pool/node_pool.gd")
const BurstScript = preload("res://scripts/client/pooled_burst.gd")
const BurstScene = preload("res://scripts/client/pooled_burst.tscn")


func run(t) -> void:
	t.current = "runtime pool: allocation, reuse and limits"
	var source := Node.new()
	source.name = "PooledObject"
	var packed := PackedScene.new()
	t.eq(packed.pack(source), OK, "test PackedScene builds")
	source.free()
	var parent := Node.new()
	var pool = PoolScript.new()
	pool.template = packed
	pool.max_idle = 2
	pool.max_active = 2
	t.eq(pool.prewarm(10), 2, "prewarm clamps to idle cap")
	t.eq(pool.prewarm(2), 0, "prewarm is idempotent")
	t.eq(pool.get_idle_count(), 2, "two cached instances")
	var first: Node = pool.acquire(parent)
	var second: Node = pool.acquire(parent)
	t.check(first != null and second != null and first != second, "distinct instances")
	t.eq(pool.get_active_count(), 2, "active accounting")
	t.eq(pool.acquire(parent), null, "hard active cap")
	t.eq(pool.get_stats()["rejected_total"], 1, "overload is observable")
	var foreign := Node.new()
	t.check(not pool.release(foreign), "foreign instance rejected")
	foreign.free()
	t.check(pool.release(first), "release succeeds")
	t.check(not pool.release(first), "double release rejected")
	var reused: Node = pool.acquire(parent)
	t.check(reused == first, "same instance reused")
	t.eq(pool.get_stats()["created_total"], 2, "reuse avoids new scene instances")
	t.eq(pool.get_stats()["reused_total"], 3, "cache hits counted")
	t.check(pool.release(reused) and pool.release(second), "active nodes returned")
	t.eq(pool.get_idle_count(), 2, "two idle instances")
	t.eq(pool.get_stats()["peak_active"], 2, "peak tracked")
	pool.clear_idle()
	t.eq(pool.get_idle_count(), 0, "idle cache freed")
	pool.max_idle = 0
	var uncached: Node = pool.acquire(parent)
	t.check(uncached != null and pool.release(uncached), "zero-cache release succeeds")
	t.eq(pool.get_idle_count(), 0, "zero cache keeps no idle nodes")
	var deleted: Node = pool.acquire(parent)
	t.check(deleted != null, "external deletion setup")
	deleted.free()
	t.eq(pool.get_active_count(), 0, "weak reference pruned after free")
	t.check(pool.get_stats()["disposed_total"] >= 3, "eviction counted")
	pool.clear_idle()
	parent.free()
	pool.free()

	t.current = "runtime pool: game particle lifecycle"
	var fx_host := Node3D.new()
	var fx_pool = PoolScript.new()
	fx_pool.template = BurstScene
	fx_pool.max_idle = 1
	t.eq(fx_pool.prewarm(1), 1, "VFX prewarm succeeds")
	var particle: Node = fx_pool.acquire(fx_host)
	t.check(particle is CPUParticles3D, "emitter is CPUParticles3D")
	if particle is CPUParticles3D:
		var emitter: CPUParticles3D = particle
		t.check(emitter.mesh is SphereMesh, "sphere mesh allocated before use")
		var original: Mesh = emitter.mesh
		particle.call("on_pool_created")
		t.check(emitter.mesh == original, "creation hook does not reallocate mesh")
	t.check(fx_pool.release(particle), "emitter return succeeds")
	t.eq(fx_pool.get_idle_count(), 1, "emitter retained")
	t.check(fx_pool.acquire(fx_host) == particle, "emitter instance reused")
	t.check(fx_pool.release(particle), "second return succeeds")
	fx_pool.clear_idle()
	fx_host.free()
	fx_pool.free()
	var standalone = BurstScript.new()
	standalone.on_pool_created()
	t.check(standalone.mesh is SphereMesh, "lazy resource initialization")
	standalone.free()

	# The stock Godot CI binary has no SceneNodePool native class; Cgame does.
	if ClassDB.class_exists("SceneNodePool"):
		t.current = "native Cgame SceneNodePool parity"
		var native = ClassDB.instantiate("SceneNodePool")
		t.check(native is Node, "native engine pool registered")
		native.template = BurstScene
		native.max_idle = 1
		native.max_active = 1
		t.eq(native.prewarm(8), 1, "native prewarm respects cache bound")
		var native_host := Node3D.new()
		var a: Node = native.acquire(native_host)
		t.check(a is CPUParticles3D, "native pool creates game particle scene")
		t.eq(native.acquire(native_host), null, "native max_active enforced")
		t.check(native.release(a), "native return succeeds")
		t.check(not native.release(a), "native double return rejected")
		t.check(native.acquire(native_host) == a, "native node reused")
		t.eq(native.get_stats()["created_total"], 1, "native cache hit avoids allocation")
		t.check(native.release(a), "native repeated lifecycle")
		native.clear_idle()
		native_host.free()
		native.free()

	t.current = "frame-sliced resident VFX pool on stock Godot"
	var budget_stock := PoolScript.new()
	_check_budgeted_residency(t, budget_stock, packed, "stock")
	budget_stock.free()
	if ClassDB.class_exists("SceneNodePool"):
		var budget_native = ClassDB.instantiate("SceneNodePool")
		if budget_native != null and budget_native.has_method("maintain_residency"):
			t.current = "native Cgame resident pool parity"
			_check_budgeted_residency(t, budget_native, packed, "native")
		budget_native.free()


	t.current = "CPU-time-sliced native and script VFX pool residency"
	t.check(not PoolScript.should_stop_maintenance(0, 2, 400),
		"zero time budget retains legacy count-only behavior")
	t.check(not PoolScript.should_stop_maintenance(1, 0, 999),
		"first indivisible allocation is never skipped")
	t.check(PoolScript.should_stop_maintenance(100, 1, 100),
		"positive CPU deadline prevents starting another scene operation")
	for mode in ["stock", "native"]:
		if mode == "native" and not ClassDB.class_exists("SceneNodePool"):
			continue
		var limited = ClassDB.instantiate("SceneNodePool") if mode == "native" else PoolScript.new()
		if limited == null or not limited.has_method("get_last_maintenance_pending_count"):
			if limited != null:
				limited.free()
			continue
		limited.template = packed
		limited.max_idle = 6
		limited.prewarm_on_ready = false
		t.eq(limited.maintain_residency(6, 2, -1), 0,
			mode + " rejects negative CPU limit atomically")
		t.eq(limited.maintain_residency(6, 2, 1000001), 0,
			mode + " rejects unbounded CPU budget atomically")
		t.eq(limited.get_idle_count(), 0, mode + " validation prevents creation")
		var created: int = limited.maintain_residency(6, 2, 1)
		t.check(created >= 1 and created <= 2,
			mode + " always creates one item but respects count limit")
		t.eq(limited.get_last_maintenance_change_count(), created,
			mode + " reports real signed creation work")
		t.eq(limited.get_last_maintenance_pending_count(), 6 - created,
			mode + " reports remaining possible idle creations")
		t.check(limited.get_last_maintenance_work_usec() >= 0,
			mode + " exposes elapsed CPU microseconds")
		while limited.get_idle_count() < 6:
			t.check(limited.maintain_residency(6, 2, 0) > 0,
				mode + " unbounded time drains capped work")
		t.eq(limited.get_last_maintenance_pending_count(), 0,
			mode + " completed residency has no pending work")
		var live_host := Node.new()
		var leased: Node = limited.acquire(live_host)
		t.check(leased != null, mode + " checked-out effect is live")
		var retired: int = limited.maintain_residency(0, 2, 1)
		t.check(retired <= -1 and retired >= -2,
			mode + " reclamation always frees at least one idle root")
		t.eq(limited.get_active_count(), 1,
			mode + " active visual effect is never removed")
		t.eq(limited.get_last_maintenance_pending_count(), limited.get_idle_count(),
			mode + " pending count excludes checked-out effects")
		t.check(limited.release(leased), mode + " live effect returns safely")
		while limited.get_idle_count() > 0:
			t.check(limited.maintain_residency(0, 2, 0) < 0,
				mode + " remaining idle effects eventually retired")
		t.eq(limited.get_last_maintenance_pending_count(), 0,
			mode + " fully drained pool has no deferred cleanup")
		live_host.free()
		limited.free()
	var effects_source: String = (load("res://scripts/client/effects.gd") as Script).source_code
	t.check(effects_source.contains("FxPolicy.pool_work_usec(level)"),
		"Albion particle emitter pool uses the quality-scaled CPU budget")
	t.check(effects_source.contains("get_last_maintenance_work_usec"),
		"Albion supports older native engines without the timed API")
	var online_source: String = FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(online_source.contains("Albion/VFXPoolMaintenanceCPUus"),
		"game profiler exposes measured pool maintenance work")
	t.check(online_source.contains("Albion/VFXPoolMaintenancePending"),
		"game profiler tracks pending resident pool changes")

static func _check_budgeted_residency(t, resident, packed: PackedScene, mode: String) -> void:
	resident.template = packed
	resident.max_idle = 6
	resident.max_active = 2
	resident.prewarm_on_ready = false
	t.eq(resident.maintain_residency(6, 0), 0, mode + " zero-step does no work")
	t.eq(resident.maintain_residency(6, 65), 0, mode + " unbounded step rejected")
	t.eq(resident.maintain_residency(-1, 2), 0, mode + " negative target rejected")
	t.eq(resident.maintain_residency(6, 2), 2, mode + " first two idle instances created")
	t.eq(resident.maintain_residency(6, 2), 2, mode + " second bounded prewarm")
	t.eq(resident.maintain_residency(6, 2), 2, mode + " third bounded prewarm")
	t.eq(resident.maintain_residency(6, 2), 0, mode + " resident target stable")
	t.eq(resident.get_idle_count(), 6, mode + " prewarmed total exactly six")
	var host := Node.new()
	var a: Node = resident.acquire(host)
	var b: Node = resident.acquire(host)
	t.check(a != null and b != null and a != b, mode + " two live instances")
	t.eq(resident.maintain_residency(6, 2), 0,
		mode + " active instances count toward target, no extra scene allocations")
	t.eq(int(resident.get_stats()["created_total"]), 6,
		mode + " only six instances created across checkout")
	t.check(resident.release(a) and resident.release(b), mode + " live instances released")
	t.eq(resident.maintain_residency(2, 1), -1, mode + " idle shrink capped to one")
	t.eq(resident.maintain_residency(2, 2), -2, mode + " idle shrink capped to two")
	t.eq(resident.maintain_residency(2, 2), -1, mode + " final idle object removed")
	t.eq(resident.get_idle_count(), 2, mode + " resident target two")
	a = resident.acquire(host)
	b = resident.acquire(host)
	t.eq(resident.maintain_residency(0, 2), 0,
		mode + " no active leases evicted by quality reduction")
	t.eq(resident.get_active_count(), 2, mode + " live gameplay effects protected")
	t.check(resident.release(a), mode + " first live effect returns normally")
	t.eq(resident.maintain_residency(0, 2), -1,
		mode + " first released idle can now be retired")
	t.check(resident.release(b), mode + " second live effect returns normally")
	t.eq(resident.maintain_residency(0, 2), -1,
		mode + " second released idle can now be retired")
	t.eq(resident.get_idle_count(), 0, mode + " zero resident footprint")
	t.eq(int(resident.get_stats()["disposed_total"]), 6,
		mode + " native/script cache retire accounting matches")
	host.free()
