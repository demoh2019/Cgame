extends RefCounted
## Native Cgame direct-space ray batches and full Godot script fallback parity.
const Spatial = preload("res://scripts/client/audio_spatial.gd")
const AudioScene = preload("res://scripts/client/audio.gd")

class BatchSpace:
	extends RefCounted
	var batches := 0
	var rays := 0

	func intersect_rays(queries: Array) -> Array:
		batches += 1
		var results: Array = []
		for ray in queries:
			results.append(_hit(ray))
		return results

	func _hit(ray: PhysicsRayQueryParameters3D) -> Dictionary:
		if ray.collision_mask != 1 or ray.collide_with_areas or not ray.collide_with_bodies:
			return {}
		return {"position": ray.from.lerp(ray.to, 0.5), "normal": Vector3.UP,
			"shape": 0, "collider_id": 0, "face_index": -1}


class SerialSpace:
	extends RefCounted
	var calls := 0

	func intersect_ray(ray: PhysicsRayQueryParameters3D) -> Dictionary:
		calls += 1
		if ray.collision_mask != 1 or ray.collide_with_areas or not ray.collide_with_bodies:
			return {}
		return {"position": ray.from.lerp(ray.to, 0.5), "normal": Vector3.UP,
			"shape": 0, "collider_id": 0, "face_index": -1}


func run(t) -> void:
	t.current = "native Cgame batch ray API is opt-in and bounded"
	var queries: Array[PhysicsRayQueryParameters3D] = []
	var first := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(10, 1, 0), 1)
	first.collide_with_areas = false
	queries.append(first)
	var second := PhysicsRayQueryParameters3D.create(Vector3(0, 2, 0), Vector3(10, 2, 0), 2)
	second.collide_with_areas = false
	queries.append(second)
	var third := PhysicsRayQueryParameters3D.create(Vector3(2, 3, 1), Vector3(8, 3, 1), 1)
	third.collide_with_areas = false
	third.collide_with_bodies = false
	queries.append(third)

	t.check(queries.size() <= 32, "game never requests an unbounded native batch")
	var batch_space := BatchSpace.new()
	var batch: Array = Spatial.trace_rays(batch_space, queries)
	t.eq(batch_space.batches, 1, "three independent queries require only one script/native boundary crossing")
	t.eq(batch_space.rays, 0, "no separate ray calls are needed in the native path")
	t.eq(batch.size(), 3, "a native batch produces exactly one result per query")
	t.check(not (batch[0] as Dictionary).is_empty(), "matching wall is returned in the first slot")
	t.check((batch[1] as Dictionary).is_empty(), "different collision mask misses without changing slot order")
	t.check((batch[2] as Dictionary).is_empty(), "disabled rigid-body collisions are honored")

	t.current = "stock Godot runs exactly the same rays in order"
	var serial := SerialSpace.new()
	var fallback: Array = Spatial.trace_rays(serial, queries)
	t.eq(serial.calls, 3, "stock Godot makes one classic intersect_ray call per query")
	t.eq(fallback, batch, "native and serial results are structurally identical")
	t.eq(Spatial.trace_rays(serial, []), [], "an empty batch does not invoke the physics world")

	t.current = "world sounds integrate multi-ray physics with original budget"
	var source: String = (AudioScene as Script).source_code
	t.check(source.contains("AudioSpatial.trace_rays(state, probe_queries)"),
		"live 3D sound issues one batch of wall checks")
	t.check(source.contains("OBSTRUCTION_RAYS_PER_TICK := 3"),
		"per-frame query budget remains three wall probes")
	t.check(source.contains("if rays >= OBSTRUCTION_RAYS_PER_TICK"),
		"request gathering stops after the fixed budget")
	t.check(source.contains("rays += 1"), "each collected query counts toward physics cost")
	t.check(source.contains('ray.collide_with_areas = false'),
		"audio treats static world bodies as occluders, not area triggers")
	t.check(source.contains('record["terrain_blocked"] = terrain_blocked'),
		"terrain heightfield obstruction remains a second source of blockage")
	t.check(source.contains('record["next_obstruction_check"] = _obstruction_clock + OBSTRUCTION_RECHECK_SECONDS'),
		"per-voice probes remain time sliced")
	t.check(source.contains('player.call("set_obstruction_amount", amount)'),
		"the existing per-source native sound filter still receives smooth obstruction")
	t.check(not source.contains("AudioServer.set_bus_volume_db(_sfx_bus,"),
		"query batching cannot mute the global game sound bus")

	t.current = "portable probing keeps a working serial fallback"
	var helper_source: String = (Spatial as Script).source_code
	t.check(helper_source.contains('space.has_method("intersect_rays")'),
		"native batch is selected through runtime API detection")
	t.check(helper_source.contains('space.call("intersect_ray", ray)'),
		"the original independent single-ray method remains the fallback")
	t.check(helper_source.contains("queries.size() <= 32"),
		"script-side batches respect the native hard limit before dispatch")
