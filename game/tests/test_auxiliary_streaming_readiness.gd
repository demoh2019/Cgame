extends RefCounted
## Unreal-style IsStreamingCompleted for the bounded native auxiliary source.
const WorldMap = preload("res://scripts/client/world_map.gd")

class ProbeChunk extends Node3D:
	var staged := false

	func has_pending_visual_detail() -> bool:
		return staged


var fail_far_chunk := false
var empty_far_chunk := true


func _make_chunk(cell: Vector3i) -> Variant:
	if fail_far_chunk and cell == Vector3i(3, 0, 0):
		return "not a valid scene node"
	if empty_far_chunk and cell == Vector3i(3, 0, 1):
		return null # Intentionally empty world cell, not a loading failure.
	var result := ProbeChunk.new()
	result.staged = cell == Vector3i(3, 0, 0)
	return result


static func _streamer(creator: Object) -> WorldStreamer:
	var s := WorldStreamer.new()
	s.axes = WorldStreamer.AXES_XZ
	s.cell_size = 16.0
	s.focus_position = Vector3(8, 0, 8)
	s.load_radius = 24.0
	s.unload_radius = 28.0
	s.max_instantiations_per_frame = 1
	s.update_interval = 100.0
	s.set_chunk_generator(Callable(creator, "_make_chunk"))
	return s


func run(t) -> void:
	t.current = "disabled and remote streaming sources fail closed"
	var streamer := _streamer(self)
	t.check(streamer.has_method("is_auxiliary_source_ready"),
		"engine exports source-specific streaming completion")
	t.eq(streamer.get_auxiliary_source_progress(), 0.0,
		"disabled source never fabricates completed scenery")
	t.check(not streamer.is_auxiliary_source_ready(),
		"disabled source never reports ready")
	t.eq(streamer.get_auxiliary_source_pending_count(), 0,
		"disabled source has no pending work")
	streamer.set_auxiliary_source(Vector3(900, 0, 8), 30.0)
	t.eq(streamer.get_auxiliary_source_progress(), 0.0,
		"remote map marker is dormant and does not show progress")
	t.check(not streamer.is_auxiliary_source_ready(),
		"distant remote source cannot be used as a loading barrier")
	streamer.clear_auxiliary_source()

	t.current = "native source progress follows actual bounded chunk generation"
	var waypoint := Vector2(40.0, 8.0)
	streamer.set_auxiliary_source(Vector3(waypoint.x, 0, waypoint.y), 12.0)
	var first_pending: int = streamer.get_auxiliary_source_pending_count()
	t.check(first_pending > 1 and first_pending <= 64,
		"pending source footprint is bounded to at most 64 cells")
	t.eq(streamer.get_auxiliary_source_progress(), 0.0,
		"unloaded source starts at zero complete")
	streamer.refresh()
	t.check(streamer.get_auxiliary_source_progress() < 1.0,
		"single-cell budget never reports all source chunks loaded immediately")
	var before: int = streamer.get_loaded_count()
	var prior_progress: float = streamer.get_auxiliary_source_progress()
	var complete := false
	for i in 128:
		streamer.refresh()
		var progress: float = streamer.get_auxiliary_source_progress()
		t.check(progress >= prior_progress and progress <= 1.0,
			"as chunks settle, loading progress does not regress")
		prior_progress = progress
		if streamer.is_auxiliary_source_ready():
			complete = true
			break
	t.check(complete, "queued source chunks eventually become ready")
	t.eq(streamer.get_auxiliary_source_progress(), 1.0,
		"loaded and intentionally empty cells count as settled")
	t.eq(streamer.get_auxiliary_source_pending_count(), 0,
		"no pending cells remain after source completion")
	t.eq(streamer.get_auxiliary_source_failed_count(), 0,
		"intentionally empty scene does not count as a failed load")
	t.check(streamer.get_loaded_count() >= before,
		"querying progress never unloads previously built cells")
	t.check(not streamer.is_cell_loaded(Vector3i(3, 0, 1)),
		"deliberately empty chunk remains uninstantiated")

	t.current = "cosmetic detail readiness is distinct from core scene loading"
	t.check(not streamer.is_auxiliary_source_ready(true),
		"staged scenery can still be pending after base chunks are loaded")
	t.check(streamer.get_auxiliary_source_progress(true) < 1.0,
		"visual-complete progress accounts for staged scenery")
	t.check(streamer.get_auxiliary_source_pending_count(true) > 0,
		"pending stage is visible through detailed source diagnostics")
	var before_details: int = streamer.get_loaded_count()
	streamer.mark_visual_details_ready(Vector3i(3, 0, 0))
	t.check(streamer.is_auxiliary_source_ready(true),
		"existing staged scenery completion toggles full readiness")
	t.eq(streamer.get_auxiliary_source_progress(true), 1.0,
		"full visual progress reaches one without extra loading")
	t.eq(streamer.get_loaded_count(), before_details,
		"readiness queries and visual completion do not change residency")
	t.eq(WorldMap.waypoint_streaming_caption(streamer, waypoint, Vector2(8, 8)),
		"Scenery prefetch: ready", "live expedition map displays readiness")
	t.eq(WorldMap.waypoint_streaming_caption(streamer, Vector2(90, 8), Vector2(8, 8)),
		"", "map never shows readiness for stale/remote waypoint data")
	streamer.clear_auxiliary_source()
	t.check(not streamer.is_auxiliary_source_ready(),
		"clearing the source immediately clears completed status")
	t.eq(streamer.get_auxiliary_source_progress(), 0.0,
		"clearing source clears diagnostic progress")
	streamer.free()

	t.current = "failed source cells block readiness and can recover on retry"
	fail_far_chunk = true
	empty_far_chunk = false
	var retry := _streamer(self)
	retry.set_auxiliary_source(Vector3(40, 0, 8), 12.0)
	for i in 128:
		retry.refresh()
		if retry.get_auxiliary_source_failed_count() > 0:
			break
	t.eq(retry.get_auxiliary_source_failed_count(), 1,
		"native failure count detects invalid procedural source chunk")
	t.check(not retry.is_auxiliary_source_ready(),
		"source with a failed cell cannot report ready")
	t.check(retry.get_auxiliary_source_progress() < 1.0,
		"failed cell is not treated as completed")
	t.eq(WorldMap.waypoint_streaming_caption(retry, waypoint, Vector2(8, 8)),
		"Scenery prefetch: retrying", "map shows recovery state rather than ready")
	fail_far_chunk = false
	retry.refresh(true)
	for i in 128:
		retry.refresh()
		if retry.is_auxiliary_source_ready():
			break
	t.check(retry.is_auxiliary_source_ready(),
		"retrying failed chunks recovers source streaming completion")
	t.eq(retry.get_auxiliary_source_failed_count(), 0,
		"successful retry clears failed source status")
	retry.free()
