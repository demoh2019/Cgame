extends RefCounted
## Opt-in procedural scene reuse: no expanded world residency, no budget bypass.
const ChunkView = preload("res://scripts/client/chunk_view.gd")

class CacheableChunk extends Node3D:
	var restores := 0
	var tier_changes: Array[bool] = []

	func can_cache_streaming_chunk() -> bool:
		return true

	func on_streaming_cache_restored() -> void:
		restores += 1

	func set_streaming_simulation_active(active: bool) -> void:
		tier_changes.append(active)
		set_process(active)


var generated: Array[Vector3i] = []


func _make_cacheable(cell: Vector3i) -> Node:
	generated.append(cell)
	var chunk := CacheableChunk.new()
	return chunk


func _make_unsafe(cell: Vector3i) -> Node:
	generated.append(cell)
	return Node3D.new()


func _streamer(method: String) -> WorldStreamer:
	var s := WorldStreamer.new()
	s.axes = WorldStreamer.AXES_XZ
	s.cell_size = 16.0
	s.load_radius = 0.0
	s.unload_radius = 0.0
	s.focus_position = Vector3(8, 0, 8)
	s.max_instantiations_per_frame = 1
	s.update_interval = 100.0
	s.set_chunk_generator(Callable(self, method))
	return s


func run(t) -> void:
	t.current = "legacy engine frees unloaded chunks without a cache"
	generated.clear()
	var legacy := _streamer("_make_cacheable")
	t.eq(legacy.max_cached_chunks, 0, "opt-in caching is disabled by default")
	legacy.refresh()
	var old := legacy.get_chunk(Vector3i.ZERO)
	legacy.focus_position = Vector3(40, 0, 8)
	legacy.refresh()
	t.eq(legacy.get_cached_chunk_count(), 0, "legacy unload never retains a scene")
	t.check(legacy.get_chunk(Vector3i.ZERO) == null,
		"unloaded cell immediately loses residency")
	legacy.focus_position = Vector3(8, 0, 8)
	legacy.refresh()
	t.eq(generated.count(Vector3i.ZERO), 2,
		"with caching disabled, return visits invoke generator again")
	t.check(legacy.get_chunk(Vector3i.ZERO) != old,
		"legacy mode never reuses a freed object identity")
	legacy.free()

	t.current = "bounded cached chunk returns with identity and frame budget preserved"
	generated.clear()
	var streamer := _streamer("_make_cacheable")
	streamer.max_cached_chunks = 2
	streamer.simulation_radius = 0.0
	streamer.refresh()
	var original := streamer.get_chunk(Vector3i.ZERO) as CacheableChunk
	t.check(original != null, "source chunk was generated")
	t.eq(streamer.get_loaded_count(), 1, "only local focus cell is visible")
	streamer.focus_position = Vector3(40, 0, 8)
	streamer.refresh()
	t.eq(streamer.get_loaded_count(), 1, "detached cached nodes are not world residents")
	t.eq(streamer.get_cached_chunk_count(), 1, "unloaded opted-in root stays cached")
	t.check(streamer.get_chunk(Vector3i.ZERO) == null,
		"get_chunk must never expose cached world objects as loaded")
	t.check(not streamer.is_cell_simulation_active(Vector3i.ZERO),
		"detached scene has no active streaming simulation tier")
	streamer.focus_position = Vector3(8, 0, 8)
	streamer.refresh()
	var restored := streamer.get_chunk(Vector3i.ZERO) as CacheableChunk
	t.check(restored == original, "return reattaches the exact same node identity")
	t.eq(original.restores, 1, "script receives one explicit restoration hook")
	t.eq(generated.count(Vector3i.ZERO), 1,
		"generator does not rebuild an identical retained chunk")
	t.eq(streamer.get_chunk_cache_hit_count(), 1,
		"native cache reports one actual hit")
	t.eq(streamer.get_cached_chunk_count(), 1,
		"the far chunk is cached after focus returns")
	t.eq(streamer.get_loaded_count(), 1, "one cache hit consumes only one scene slot")
	t.check(streamer.is_cell_simulation_active(Vector3i.ZERO),
		"restored scene has its near simulation tier")
	streamer.unload_all()
	t.eq(streamer.get_cached_chunk_count(), 0,
		"manual unload_all releases detached cached resources")
	t.eq(streamer.get_loaded_count(), 0, "manual unload_all releases active chunk")
	streamer.free()

	t.current = "one-slot backtrack protects a newly requested cached destination"
	generated.clear()
	var one := _streamer("_make_cacheable")
	one.max_cached_chunks = 1
	one.refresh()
	var first := one.get_chunk(Vector3i.ZERO)
	one.focus_position = Vector3(40, 0, 8)
	one.refresh()
	one.focus_position = Vector3(8, 0, 8)
	one.refresh()
	t.check(one.get_chunk(Vector3i.ZERO) == first,
		"current requested old cell is preserved during the new chunk's unload")
	t.eq(generated.count(Vector3i.ZERO), 1,
		"one-slot cache avoids terrain rebuild on immediate reverse motion")
	t.eq(one.get_chunk_cache_hit_count(), 1,
		"one-slot return counts a genuine reuse hit")
	t.check(one.get_cached_chunk_count() <= 1,
		"requested-cell protection still respects the strict cache cap")
	one.free()

	t.current = "least recently unloaded chunks are evicted at a strict cap"
	generated.clear()
	var lru := _streamer("_make_cacheable")
	lru.max_cached_chunks = 1
	lru.refresh()
	lru.focus_position = Vector3(40, 0, 8)
	lru.refresh()
	t.eq(lru.get_cached_chunk_count(), 1, "one old scene kept while next is loaded")
	lru.focus_position = Vector3(72, 0, 8)
	lru.refresh()
	t.eq(lru.get_cached_chunk_count(), 1, "cache does not grow beyond its cap")
	t.check(lru.get_chunk_cache_eviction_count() >= 1,
		"oldest detached chunk evicted on capacity pressure")
	lru.focus_position = Vector3(8, 0, 8)
	lru.refresh()
	t.eq(generated.count(Vector3i.ZERO), 2,
		"evicted scene is generated afresh when revisited")
	t.eq(lru.get_chunk_cache_hit_count(), 0, "eviction cannot create a phantom hit")
	lru.clear_cached_chunks()
	t.eq(lru.get_cached_chunk_count(), 0, "explicit cache clear drops all detached scenes")
	t.eq(lru.get_chunk_cache_eviction_count(), 0, "clear resets cache diagnostics")
	lru.free()

	t.current = "generator safety and grid changes invalidate cache"
	generated.clear()
	var invalidation := _streamer("_make_cacheable")
	invalidation.max_cached_chunks = 2
	invalidation.refresh()
	invalidation.focus_position = Vector3(40, 0, 8)
	invalidation.refresh()
	t.eq(invalidation.get_cached_chunk_count(), 1, "cache populated before reconfiguration")
	invalidation.cell_size = 32.0
	t.eq(invalidation.get_cached_chunk_count(), 0,
		"changing cell coordinates discards stale node geometry")
	invalidation.refresh()
	invalidation.focus_position = Vector3(104, 0, 8)
	invalidation.refresh()
	t.check(invalidation.get_cached_chunk_count() > 0,
		"new grid produces cache entries normally")
	invalidation.set_chunk_generator(Callable(self, "_make_unsafe"))
	t.eq(invalidation.get_cached_chunk_count(), 0,
		"changing the generator invalidates cached scene objects")
	invalidation.focus_position = Vector3(8, 0, 8)
	invalidation.refresh()
	invalidation.focus_position = Vector3(104, 0, 8)
	invalidation.refresh()
	t.eq(invalidation.get_cached_chunk_count(), 0,
		"without a root opt-in method, the engine always frees on unload")
	invalidation.max_cached_chunks = 9999
	t.eq(invalidation.max_cached_chunks, 16, "native count is hard-capped at 16")
	invalidation.max_cached_chunks = -100
	t.eq(invalidation.max_cached_chunks, 0, "negative budgets become the safe legacy mode")
	invalidation.free()

	t.current = "Albion After chunk explicitly resets deferred cosmetic work on reuse"
	var view := ChunkView.new()
	t.check(view.can_cache_streaming_chunk(),
		"real game scenery opts into immutable chunk reuse")
	view.set_streaming_simulation_active(false)
	view.on_streaming_cache_restored()
	t.check(not view.is_processing(),
		"cosmetic LOD remains paused if a cached scene is still far away")
	view.set_streaming_simulation_active(true)
	view.on_streaming_cache_restored()
	t.check(view.is_processing(),
		"restored near-field chunk resumes client-only updates")
	view.free()
