extends RefCounted
## Sky cubemap refreshes are decoupled from frame time and light movement.
## The sky shader is source-checked because this regression otherwise silently re-enables realtime radiance.

const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")


func run(t) -> void:
	t.current = "sky reflection update budgets"
	var low: float = float(VisualProfiles.settings(0)["sky_refresh_interval"])
	var balanced: float = float(VisualProfiles.settings(1)["sky_refresh_interval"])
	var high: float = float(VisualProfiles.settings(2)["sky_refresh_interval"])
	var ultra: float = float(VisualProfiles.settings(3)["sky_refresh_interval"])
	t.check(low > balanced and balanced > high and high > ultra,
		"higher graphics tiers refresh reflections more often")
	t.check(ultra >= 0.12, "even Ultra bounds reflection recomputes")
	t.check(low <= 2.0, "Performance refreshes sky reflections periodically")

	t.current = "sky radiance dependency contract"
	var source: String = FileAccess.get_file_as_string("res://assets/shaders/sky.gdshader")
	t.check(not source.is_empty(), "sky shader must exist")
	t.check(source.contains("uniform float sky_time"), "sky animation is driven by cached time")
	t.check(source.contains("uniform vec3 sun_direction"), "sky sun direction is cached")
	t.check(not source.contains("TIME * drift"), "animated panoramas cannot force per-frame radiance updates")
	t.check(not source.contains("sin(TIME"), "star animation cannot force per-frame radiance updates")
	t.check(not source.contains("LIGHT0_DIRECTION"), "moving directional lights cannot directly invalidate sky radiance")
	t.check(not source.contains("LIGHT0_COLOR"), "moving directional light colors cannot directly invalidate sky radiance")
