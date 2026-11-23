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
	t.current = "GPU timings preserve clarity under CPU load"
	c.configure(1)
	var changed_gpu := false
	for i in 240:
		# 25 FPS due to gameplay CPU work, but GPU needs only 8 ms.
		changed_gpu = c.sample_frame(1.0 / 25.0, 8.0) or changed_gpu
	t.check(not changed_gpu and c.at_ceiling(),
		"CPU-bound scenes keep native tier scale when GPU has headroom")
	changed_gpu = false
	for i in 480:
		# 120 FPS CPU update, but 33 ms spent on actual GPU rendering.
		changed_gpu = c.sample_frame(1.0 / 120.0, 33.0) or changed_gpu
	t.check(changed_gpu and c.scale < 0.77,
		"GPU-bound rendering scales down despite a short CPU process delta")
	t.current = "CPU-bound frames do not trigger resolution recovery"
	c.configure(1)
	for i in 500:
		c.sample_frame(1.0 / 120.0, 33.0)
	var reduced_scale: float = c.scale
	t.check(reduced_scale < 0.77,
		"sustained slow GPU first reduces pixel load")
	var premature_upgrade := false
	for i in 1600:
		premature_upgrade = c.sample_frame(1.0 / 25.0, 7.0) or premature_upgrade
	t.check(not premature_upgrade and c.scale <= reduced_scale + 0.00001,
		"slow game CPU cannot drive premature GPU resolution increases")
	var legitimate_upgrade := false
	for i in 500:
		legitimate_upgrade = c.sample_frame(1.0 / 60.0, 7.0) or legitimate_upgrade
	t.check(legitimate_upgrade and c.scale > reduced_scale,
		"healthy GPU and game thread restore resolution after hysteresis")

	t.near(Adaptive.render_frame_seconds(1.0 / 30.0, 0.0), 1.0 / 30.0, 0.00001,
		"zero/unavailable GPU timer preserves legacy frame-pacing fallback")
	t.near(Adaptive.render_frame_seconds(1.0 / 30.0, 8.0), 0.008, 0.00001,
		"valid milliseconds are converted to seconds exactly once")
	t.near(Adaptive.render_frame_seconds(1.0 / 30.0, INF), 1.0 / 30.0, 0.00001,
		"invalid GPU timings cannot poison adaptive quality")
	t.near(Adaptive.render_frame_seconds(1.0 / 30.0, 200.0), 1.0 / 30.0, 0.00001,
		"single GPU shader-compilation spikes are rejected")
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


	t.current = "MetalFX hardware floor keeps dynamic resolution in a supported range"
	c.configure(1, 0.71)
	t.near(c.floor_scale, 0.71, 0.00001,
		"device minimum overrides the ordinary Balanced low-resolution floor")
	var touched_hardware_floor := false
	for i in 1500:
		touched_hardware_floor = c.sample_frame(1.0 / 30.0, 36.0) or touched_hardware_floor
	t.check(touched_hardware_floor and c.at_floor(),
		"GPU-limited Metal rendering settles at its supported scale")
	t.near(c.scale, 0.71, 0.00001,
		"adaptive scaler never requests an illegal MetalFX input size")
	c.configure(1, NAN)
	t.near(c.floor_scale, 0.65, 0.00001,
		"invalid hardware limit restores the original FSR2 floor")
	c.configure(0, 0.95)
	t.near(c.floor_scale, 0.59, 0.00001,
		"hardware minimum cannot push Performance above its cost ceiling")
	c.configure(3, 0.91)
	t.near(c.floor_scale, 0.91, 0.00001,
		"Ultra retains full native detail above the GPU's minimum scale")


	t.current = "unsupported MetalFX floor cannot trap Performance at its ceiling"
	c.configure(0, 0.72)
	t.near(c.floor_scale, 0.52, 0.00001,
		"device minimum above Performance's 0.59 ceiling forces FSR2 budget")
	var got_reduction := false
	for i in 480:
		got_reduction = c.sample_frame(1.0 / 30.0, 34.0) or got_reduction
	t.check(got_reduction and c.at_floor(),
		"prolonged GPU bottleneck can still recover 3D rendering performance")
	t.near(c.scale, 0.52, 0.00001,
		"FSR2 performance floor stays reachable after MetalFX rejection")
	c.configure(1, 0.80)
	t.near(c.floor_scale, 0.65, 0.00001,
		"Balanced rejects an unsupported minimum above its 0.77 ceiling")
	c.configure(1, 0.70)
	t.near(c.floor_scale, 0.70, 0.00001,
		"supported Balanced GPU retains MetalFX's actual safe floor")
