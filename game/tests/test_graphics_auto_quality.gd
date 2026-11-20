extends RefCounted
## The FPS budget controller must be deterministic, use hysteresis and ignore single stalls.

const GraphicsAutoQuality = preload("res://scripts/client/graphics_auto_quality.gd")


func run(t) -> void:
	var quality := GraphicsAutoQuality.new()
	t.current = "adaptive graphics presets"
	t.eq(quality.mode, "auto", "automatic quality is the default")
	t.eq(quality.level, 1, "start with balanced vegetation")
	t.eq(quality.preset()["grass_end"], 60.0, "default grass view distance")
	t.check(not quality.set_mode("ultra-unavailable"), "unknown preset is rejected")
	t.check(quality.set_mode("quality"), "manual quality preset can be selected")
	t.eq(quality.level, 2, "quality increases the detail budget")
	t.check(quality.set_mode("performance"), "manual performance preset can be selected")
	t.eq(quality.level, 0, "performance reduces the detail budget")
	for frame in 240:
		if frame == 0:
			t.check(not quality.sample_frame(1.0 / 15.0), "manual mode does not auto-switch")
		else:
			quality.sample_frame(1.0 / 15.0)
	t.eq(quality.level, 0, "manual setting survives low FPS")
	t.check(quality.set_mode("auto"), "auto mode can be selected")
	t.current = "adaptive hysteresis"
	var changed := false
	for frame in 150:
		changed = quality.sample_frame(1.0 / 30.0) or changed
	t.check(changed, "sustained 30 FPS reduces detail")
	t.eq(quality.level, 0, "low FPS selects performance")
	t.check(not quality.sample_frame(1.0), "single long stall is ignored")
	t.eq(quality.level, 0, "one stall does not change quality")
	changed = false
	for frame in 1320:
		changed = quality.sample_frame(1.0 / 60.0) or changed
	t.check(changed, "sustained good FPS eventually recovers detail")
	t.check(quality.level >= 1, "recovered settings are at least balanced")
