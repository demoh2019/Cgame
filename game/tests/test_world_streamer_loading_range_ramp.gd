extends RefCounted
## WorldStreamer startup loading-area ramp + live Albion After integration.
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")

var generated: Array[Vector3i] = []


func _chunk(cell: Vector3i) -> Node:
	generated.append(cell)
	return Node3D.new()


func run(t) -> void:
	t.current = "default world range is unchanged"
	var legacy := WorldStreamer.new()
	legacy.load_radius = 64.0
	t.near(legacy.get_effective_load_radius(), 64.0, 0.001,
		"new engine defaults to configured full range")
	t.near(legacy.get_loading_range_area_percent(), 100.0, 0.001,
		"non-opt-in worlds request their entire 2D area")
	t.check(not legacy.is_loading_range_ramping(), "legacy streaming never ramps")
	legacy.free()

	t.current = "progressive focus radius and real procedural chunk loading"
	generated.clear()
	var streamer := WorldStreamer.new()
	streamer.axes = WorldStreamer.AXES_XZ
	streamer.cell_size = 16.0
	streamer.load_radius = 48.0
	streamer.unload_radius = 80.0
	streamer.focus_position = Vector3(8, 0, 8)
	streamer.update_interval = 100.0
	streamer.max_instantiations_per_frame = 128
	streamer.set_chunk_generator(Callable(self, "_chunk"))
	streamer.begin_loading_range_ramp(0.25, 0.5, 2.0)
	t.check(streamer.is_loading_range_ramping(), "opt-in ramp starts immediately")
	t.near(streamer.get_effective_load_radius(), 24.0, 0.001,
		"25 percent area requests only half the usual radius")
	streamer.refresh()
	var initial: int = streamer.get_loaded_count()
	t.check(initial > 0, "player and nearby terrain load during initial stage")
	streamer.advance_loading_range_ramp(0.25)
	t.near(streamer.get_effective_load_radius(), 24.0, 0.001,
		"delay holds the smaller initial area")
	streamer.advance_loading_range_ramp(1.25)
	t.near(streamer.get_loading_range_area_percent(), 62.5, 0.001,
		"halfway through the expansion loads 62.5 percent of configured area")
	streamer.refresh()
	var midway: int = streamer.get_loaded_count()
	t.check(midway > initial, "middle stage requests additional real terrain chunks")
	streamer.advance_loading_range_ramp(1.0)
	streamer.refresh()
	t.check(streamer.get_loaded_count() > midway,
		"full radius requests additional cells without manual teleport")
	t.check(not streamer.is_loading_range_ramping(), "ramp completes normally")
	t.near(streamer.get_effective_load_radius(), 48.0, 0.001,
		"configured full loading distance is restored")
	t.near(streamer.load_radius, 48.0, 0.001,
		"startup ramp never overwrites user graphics setting")
	t.near(streamer.unload_radius, 80.0, 0.001,
		"loaded world keeps the original hysteresis margin")
	streamer.unload_all()
	streamer.free()

	t.current = "bounds, cancel, and three-dimensional volume semantics"
	var config := WorldStreamer.new()
	config.load_radius = 64.0
	config.axes = WorldStreamer.AXES_XYZ
	config.begin_loading_range_ramp(0.125, 0.0, 2.0)
	t.near(config.get_effective_load_radius(), 32.0, 0.001,
		"one eighth 3D volume reduces spatial radius by half")
	config.advance_loading_range_ramp(-1.0)
	t.near(config.get_loading_range_area_percent(), 12.5, 0.001,
		"negative elapsed time is ignored")
	config.cancel_loading_range_ramp()
	t.check(not config.is_loading_range_ramping(), "cancel stops the ramp")
	t.near(config.get_effective_load_radius(), 64.0, 0.001,
		"cancel restores full load eligibility without scene work")
	config.begin_loading_range_ramp(-1.0, 0.0, 1.0)
	t.near(config.get_loading_range_area_percent(), 5.0, 0.001,
		"invalid low fraction retains a nonzero playable footprint")
	config.advance_loading_range_ramp(2.0)
	t.near(config.get_loading_range_area_percent(), 100.0, 0.001,
		"late game-time step completes bounded expansion")
	config.begin_loading_range_ramp(0.25, 0.0, 0.0)
	t.check(not config.is_loading_range_ramping(), "zero-time ramp is a no-op")
	config.free()

	t.current = "Albion After starts and profiles the native range ramp"
	var client_source := FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(client_source.contains('has_method("begin_loading_range_ramp")'),
		"client enables new engine API conditionally")
	t.check(client_source.contains("GraphicsQuality.startup_streaming_area_for_quality"),
		"client startup area follows actual graphics preference")
	t.check(client_source.contains("Albion/StreamLoadAreaPct"),
		"performance profiler shows current loaded area percentage")
	for level in 4:
		var frac: float = GraphicsQuality.startup_streaming_area_for_quality(level)
		t.check(frac > 0.0 and frac <= 1.0,
			"each graphics tier keeps nearby terrain eligible")
		t.check(GraphicsQuality.startup_streaming_ramp_duration(level) > 0.0,
			"each tier automatically expands to full configured radius")
