extends RefCounted
## Extra World Partition-style source with native load/unload and game map integration.
const StreamingPolicy = preload("res://scripts/client/world_streaming_policy.gd")

var _generated: Array[Vector3i] = []


func _make_chunk(cell: Vector3i) -> Node:
	_generated.append(cell)
	return Node3D.new()


func run(t) -> void:
	t.current = "auxiliary world streaming starts disabled and has a strict radius cap"
	var streamer := WorldStreamer.new()
	streamer.axes = WorldStreamer.AXES_XZ
	streamer.cell_size = 16.0
	streamer.focus_position = Vector3(8, 0, 8)
	streamer.load_radius = 24.0
	streamer.unload_radius = 28.0
	streamer.max_instantiations_per_frame = 1
	streamer.update_interval = 100.0
	streamer.set_chunk_generator(Callable(self, "_make_chunk"))
	t.check(streamer.has_method("set_auxiliary_source"),
		"native streamer supports an optional World Partition-like streaming source")
	t.check(not streamer.has_auxiliary_source(),
		"legacy worlds have no extra residency without explicit opt-in")
	t.eq(streamer.get_auxiliary_source_radius(), 0.0,
		"disabled source contributes no streaming radius")
	_generated.clear()
	streamer.refresh()
	t.eq(_generated.size(), 1,
		"adding a second source does not raise the per-frame generation count")
	t.check(streamer.is_cell_loaded(Vector3i(0, 0, 0)),
		"the player's authoritative home cell is always the first cell loaded")

	t.current = "a nearby map destination preloads visual scenery outside player radius"
	var point := Vector3(40, 0, 8)
	streamer.set_auxiliary_source(point, 300.0)
	t.check(streamer.has_auxiliary_source(), "nearby source is enabled")
	t.eq(streamer.get_auxiliary_source_position(), point,
		"engine stores the requested secondary local position")
	t.near(streamer.get_auxiliary_source_radius(), 32.0, 0.0001,
		"native radius is capped at two streaming cells, even for extreme values")
	streamer.set_auxiliary_source(point, 12.0)
	for i in 24:
		streamer.refresh()
	var farther := Vector3i(3, 0, 0)
	t.check(streamer.is_cell_loaded(farther),
		"map target cell outside player's 24 m radius was prefetched")
	t.check(_generated.has(farther),
		"actual streamed chunk generator received the auxiliary cell")
	t.check(streamer.is_cell_loaded(Vector3i(0, 0, 0)),
		"normal focus-world residency is preserved")
	var calls: int = _generated.size()
	streamer.refresh()
	t.check(_generated.size() <= calls + 1,
		"secondary source cannot bypass shared per-refresh count budget")
	streamer.clear_auxiliary_source()
	t.check(not streamer.has_auxiliary_source(),
		"removing waypoint disables extra residency immediately")
	streamer.refresh()
	t.check(not streamer.is_cell_loaded(farther),
		"stale prefetched cells are released beyond the main unload radius")
	streamer.free()

	t.current = "distant map pins cannot instantiate a second world island"
	_generated.clear()
	var remote := WorldStreamer.new()
	remote.cell_size = 16.0
	remote.focus_position = Vector3(8, 0, 8)
	remote.load_radius = 24.0
	remote.unload_radius = 28.0
	remote.max_instantiations_per_frame = 1
	remote.update_interval = 100.0
	remote.set_chunk_generator(Callable(self, "_make_chunk"))
	remote.set_auxiliary_source(Vector3(600, 0, 8), 500.0)
	t.near(remote.get_auxiliary_source_radius(), 32.0, 0.0001,
		"even a far-away request never creates a 500 m source radius")
	for i in 10:
		remote.refresh()
	t.check(remote.get_loaded_count() > 0,
		"player's nearby cells still load normally")
	for cell in _generated:
		t.check(cell.x < 10,
			"far quest marker cannot generate chunks hundreds of metres away")
	remote.free()

	t.current = "AStar waypoint route detours and native stream scheduling"
	var corridor_streamer := WorldStreamer.new()
	corridor_streamer.axes = WorldStreamer.AXES_XZ
	corridor_streamer.cell_size = 16.0
	corridor_streamer.focus_position = Vector3(8, 0, 8)
	corridor_streamer.load_radius = 32.0
	corridor_streamer.unload_radius = 40.0
	corridor_streamer.max_instantiations_per_frame = 1
	corridor_streamer.update_interval = 100.0
	corridor_streamer.set_chunk_generator(Callable(self, "_make_chunk"))
	var clear_waypoint := Vector2(40, 8)
	var direct: Array[Vector3i] = StreamingPolicy.plan_waypoint_route(
		corridor_streamer, clear_waypoint, corridor_streamer.focus_position)
	t.eq(direct, [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0)],
		"the direct private waypoint corridor passes through adjacent XZ cells")
	t.eq(StreamingPolicy.plan_waypoint_route(corridor_streamer,
		Vector2(-24, 8), corridor_streamer.focus_position),
		[Vector3i(0, 0, 0), Vector3i(-1, 0, 0), Vector3i(-2, 0, 0)],
		"straight westbound corridor follows adjacent cells")
	t.eq(StreamingPolicy.plan_waypoint_route(corridor_streamer,
		Vector2(8, 8), corridor_streamer.focus_position), [Vector3i.ZERO],
		"same-cell waypoint returns exactly one cell")
	t.eq(StreamingPolicy.plan_waypoint_route(corridor_streamer,
		clear_waypoint, corridor_streamer.focus_position, [Vector3i(1, 1, 0)]),
		direct, "obstacles on another floor do not block surface streaming")
	var detour: Array[Vector3i] = StreamingPolicy.plan_waypoint_route(
		corridor_streamer, clear_waypoint, corridor_streamer.focus_position,
		[Vector3i(1, 0, 0)])
	t.check(detour.size() > direct.size() and detour.size() <= 64,
		"a dynamic blocked cell produces a bounded longer alternative")
	t.check(not detour.has(Vector3i(1, 0, 0)),
		"blocked hazards are avoided by the AStarGrid2D route")
	for i in range(1, detour.size()):
		var move: Vector3i = detour[i] - detour[i - 1]
		t.eq(absi(move.x) + absi(move.y) + absi(move.z), 1,
			"all alternative route steps share one orthogonal cell edge")
	t.check(StreamingPolicy.plan_waypoint_route(corridor_streamer,
		Vector2(900, 8), corridor_streamer.focus_position).is_empty(),
		"no distant destination starts expensive AStar planning")
	t.check(StreamingPolicy.plan_waypoint_route(corridor_streamer,
		clear_waypoint, corridor_streamer.focus_position,
		[Vector3i(0, 0, 0)]).is_empty(),
		"blocked player position never creates a fabricated route")
	t.check(corridor_streamer.has_method("set_route_cells"),
		"WorldStreamer exposes native bounded corridor priority hints")
	StreamingPolicy.apply_waypoint_route(
		corridor_streamer, clear_waypoint, corridor_streamer.focus_position)
	t.eq(corridor_streamer.get_route_cells(), direct,
		"real game policy submits planned route cells to native WorldStreamer")
	var bad_route: Array[Vector3i] = [Vector3i.ZERO, Vector3i(2, 0, 0)]
	t.check(not corridor_streamer.set_route_cells(bad_route),
		"engine rejects teleport shortcuts and leaves previous route intact")
	t.eq(corridor_streamer.get_route_cells(), direct,
		"invalid corridor cannot mutate the last valid engine route")
	var too_long: Array[Vector3i] = []
	for i in 65:
		too_long.append(Vector3i(i, 0, 0))
	t.check(not corridor_streamer.set_route_cells(too_long),
		"engine enforces a strict 64-cell route memory cap")
	_generated.clear()
	corridor_streamer.refresh()
	t.eq(_generated[0], Vector3i.ZERO,
		"player focus chunk remains first despite the map's route hint")
	corridor_streamer.refresh()
	t.eq(_generated[1], Vector3i(1, 0, 0),
		"native generator prioritizes next waypoint corridor cell")
	t.eq(corridor_streamer.get_loaded_count(), 2,
		"route priority cannot bypass the shared per-frame chunk budget")
	corridor_streamer.set_route_cells(too_long.slice(0, 64))
	for i in 8:
		corridor_streamer.refresh()
	for loaded_cell in corridor_streamer.get_loaded_cells():
		t.check(loaded_cell.x < 3,
			"route hints cannot expand residency to distant map segments")
	StreamingPolicy.apply_waypoint_route(corridor_streamer,
		Vector2(900, 8), corridor_streamer.focus_position)
	t.check(corridor_streamer.get_route_cells().is_empty(),
		"out-of-range map pin clears old route scheduling immediately")
	corridor_streamer.free()

	t.current = "live personal waypoint policy has distance, finite and bike guards"
	t.check(StreamingPolicy.waypoint_is_near(Vector2(40, 8),
		Vector3(8, 0, 8), 24.0, 16.0),
		"nearby target qualifies for auxiliary streaming")
	t.check(not StreamingPolicy.waypoint_is_near(Vector2(600, 8),
		Vector3(8, 0, 8), 24.0, 16.0),
		"the far side of the island never activates secondary loading")
	t.check(not StreamingPolicy.waypoint_is_near(Vector2(INF, INF),
		Vector3(8, 0, 8), 24.0, 16.0),
		"clearing the waypoint does not activate an invalid source")
	t.check(StreamingPolicy.waypoint_radius(16.0, true) >
		StreamingPolicy.waypoint_radius(16.0, false),
		"mounted players prefetch slightly more of the destination")
	t.check(StreamingPolicy.waypoint_radius(16.0, true) <= 32.0,
		"the game's bike bonus never exceeds the engine's native cap")

	var marker := WorldStreamer.new()
	marker.cell_size = 16.0
	marker.load_radius = 24.0
	StreamingPolicy.apply_waypoint(marker, Vector2(40, 8), Vector3(8, 0, 8), false)
	t.check(marker.has_auxiliary_source(),
		"the live client map marker enables Cgame's secondary source")
	t.eq(marker.get_auxiliary_source_position(), Vector3(40, 0, 8),
		"the point's north/east location is passed to the XZ streaming grid")
	t.near(marker.get_auxiliary_source_radius(), 24.0, 0.0001,
		"walking uses only one and a half cells of additional scenery")
	StreamingPolicy.apply_waypoint(marker, Vector2(40, 8), Vector3(8, 0, 8), true)
	t.near(marker.get_auxiliary_source_radius(), 32.0, 0.0001,
		"mounting increases the nearby waypoint prefetch region")
	StreamingPolicy.apply_waypoint(marker, Vector2(600, 8), Vector3(8, 0, 8), true)
	t.check(not marker.has_auxiliary_source(),
		"moving away from a pin immediately disables the extra loading source")
	StreamingPolicy.apply_waypoint(marker, Vector2(40, 8), Vector3(8, 0, 8), false)
	StreamingPolicy.apply_waypoint(marker, Vector2(INF, INF), Vector3(8, 0, 8), false)
	t.check(not marker.has_auxiliary_source(),
		"clearing private navigation stops auxiliary streaming")
	marker.free()

	t.current = "Albion After integrates map waypoints with its real procedural streamer"
	var online: String = FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(online.contains("WorldStreamingPolicy.apply_waypoint(streamer, world_map.waypoint, position,"),
		"actual client requests early chunks near personal waypoints")
	t.check(online.contains("streamer.max_chunk_work_usec = 2500"),
		"extra source reuses the existing 2.5 ms soft CPU budget")
	t.check(online.contains("streamer.max_instantiations_per_frame = 3"),
		"extra source cannot bypass Cgame's per-frame generation cap")
	t.check(online.contains("moved.length_squared() < 576.0"),
		"teleport protection still resets invalid predicted movement")
