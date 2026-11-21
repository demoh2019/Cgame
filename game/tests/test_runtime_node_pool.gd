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
