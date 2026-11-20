extends RefCounted
## Hysteresis, stall immunity, resolution floors and recovery.
const Adaptive = preload("res://scripts/client/graphics_dynamic_resolution.gd")


func run(t) -> void:
	var c := Adaptive.new()
	t.current = "auto frame timing is safe and stable"
	t.eq(c.level, 1, "Balanced auto starts first")
	t.near(c.scale, 0.77, 0.0001, "native-ish initial quality")
	for delta in [NAN, INF, -2.0, 0.8, 0.0]:
		t.check(not c.sample_frame(delta), "bad/stalled time ignored")
	var changed := false
	for i in 120:
		changed = c.sample_frame(1.0 / 30.0) or changed
	t.check(changed and c.scale < 0.77 and c.scale >= 0.65,
		"sustained slow FPS steps 3D render scale down")
	for i in 1400:
		c.sample_frame(1.0 / 30.0)
	t.check(c.at_floor(), "slow GPU reaches bounded quality floor")
	t.near(c.scale, 0.65, 0.0001, "never lowers beyond tier floor")
	t.check(not c.sample_frame(1.0 / 30.0), "no repeated resize at floor")
	changed = false
	for i in 2400:
		changed = c.sample_frame(1.0 / 60.0) or changed
	t.check(changed and c.at_ceiling(), "sustained fast FPS recovers clarity")
	t.near(c.scale, 0.77, 0.0001, "never exceeds balanced ceiling")
	t.current = "preset changes reset filters without oscillation"
	c.configure(2)
	t.near(c.scale, 1.0, 0.0001, "High starts at native resolution")
	for i in 15:
		t.check(not c.sample_frame(1.0 / 30.0),
			"short frame streak cannot resize")
	c.configure(-500)
	t.eq(c.level, 0, "low clamp")
	t.near(c.scale, 0.59, 0.0001, "Performance ceiling")
	c.configure(500)
	t.eq(c.level, 3, "high clamp")
	t.near(c.scale, 1.0, 0.0001, "Ultra ceiling")
