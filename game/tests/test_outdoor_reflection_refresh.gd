extends RefCounted
## On-demand weather-aware reflection recapture; pure scheduler + fork API.
const Budget = preload("res://scripts/client/outdoor_reflection_budget.gd")


func run(t) -> void:
	t.current = "bounded weather refresh without per-frame cubemap captures"
	var first := Budget.weather_signature(0.7, 0.0)
	var twilight := Budget.weather_signature(0.49, 0.0)
	var storm := Budget.weather_signature(0.7, 0.58)
	t.check(Budget.weather_changed(first, twilight),
		"sunset drift requires an updated architectural reflection")
	t.check(Budget.weather_changed(first, storm),
		"storm front requires an updated wet-metal/stone reflection")
	t.check(not Budget.weather_changed(first, Vector2(0.69, 0.1)),
		"small lighting fluctuations do not rerender a cubemap")
	t.check(Budget.WEATHER_RECAPTURE_INTERVAL >= 15.0,
		"one pool-wide recapture needs at least 15 seconds of separation")
	t.check(Budget.WEATHER_RECAPTURE_INTERVAL > Budget.CAPTURE_COOLDOWN,
		"slow environment refresh cannot interrupt initial room capture")
	t.eq(Budget.weather_signature(5.0, -2.0), Vector2(1.0, 0.0),
		"weather bounds cannot generate invalid cubemap intensities")
	for bad in [NAN, INF, -INF]:
		t.eq(Budget.weather_signature(bad, 0.0), Vector2(-1.0, -1.0),
			"invalid daylight never requests a native capture")
		t.eq(Budget.weather_signature(0.0, bad), Vector2(-1.0, -1.0),
			"invalid storm does not contaminate the reflection atlas")
	t.check(not Budget.weather_changed(Vector2(-1.0, -1.0), storm),
		"unassigned or unknown captures cannot trigger GPU work")
	t.check(not Budget.weather_changed(first, Vector2(-1.0, -1.0)),
		"missing atmosphere remains safely idle")

	t.current = "engine native UPDATE_ONCE request preserves atlas and transform"
	var probe: ReflectionProbe = Budget.make_probe(Budget.settings(3, "forward_plus"))
	t.eq(probe.update_mode, ReflectionProbe.UPDATE_ONCE,
		"all weather captures remain in economical ONCE mode")
	t.check(probe.has_method("request_update"),
		"custom Godot fork exposes manual cubemap recapture")
	var authored_position := Vector3(4.5, 1.2, -6.1)
	probe.position = authored_position
	if probe.has_method("request_update"):
		probe.call("request_update") # unattached probe must not allocate an atlas
	t.eq(probe.position, authored_position,
		"on-demand capture never changes actual node coordinates")
	t.eq(probe.update_mode, ReflectionProbe.UPDATE_ONCE,
		"request does not switch the probe to ALWAYS or reduce atlas size")
	t.check(probe.box_projection and not probe.interior and not probe.enable_shadows,
		"real box-reflection and six-face no-shadows budgets stay intact")
	probe.free()

	t.current = "active game pipeline shares one atmospheric weather source"
	var manager: String = (Budget as Script).source_code
	var online: Script = load("res://scripts/client/online_main.gd") as Script
	t.check(online != null, "online world script parses")
	if online != null:
		t.check(online.source_code.contains(
			"outdoor_reflections.atmosphere = atmosphere"),
			"world passes smoothed actual sky/weather into the one probe pool")
	t.check(manager.contains('float(atmosphere.get("light_level"))') and
		manager.contains('float(atmosphere.get("storm"))'),
		"captures reflect game daylight and storm rather than invented time")
	t.check(manager.contains('_weather_refresh_elapsed >= WEATHER_RECAPTURE_INTERVAL'),
		"all probes share one global minimum weather-refresh interval")
	t.check(manager.contains('_probes[i].has_method("request_update")') and
		manager.contains('_probes[i].call("request_update")'),
		"stock Godot can run without native on-demand API")
	t.check(manager.contains("_weather_at_capture.clear()"),
		"quality downgrade releases weather history and cubemaps")
