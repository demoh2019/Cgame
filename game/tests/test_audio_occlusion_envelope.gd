extends RefCounted
## Independently timed 3D audio obstruction, with matching native + stock Godot behavior.
const Spatial = preload("res://scripts/client/audio_spatial.gd")
const AudioScene = preload("res://scripts/client/audio.gd")


func run(t) -> void:
	t.current = "attack is fast and release is gentle"
	var attack: float = Spatial.smooth_obstruction(0.0, 1.0, 0.08)
	t.check(attack > 0.63 and attack < 0.64,
		"the source loses high frequencies within one attack time constant")
	var release: float = Spatial.smooth_obstruction(1.0, 0.0, 0.08)
	t.check(release > 0.69 and release < 0.70,
		"regaining the open path takes longer than losing it")
	t.eq(Spatial.smooth_obstruction(0.45, 1.0, 0.0), 0.45,
		"zero-time integration leaves filters unchanged")
	t.eq(Spatial.smooth_obstruction(0.45, 0.45, 0.2), 0.45,
		"stable audio never resubmits identical mixer state")
	t.eq(Spatial.smooth_obstruction(0.0, 1.0, 10.0), 1.0,
		"long pauses settle exactly instead of creating infinite updates")

	t.current = "same occlusion evolution at different physics frame rates"
	var sixty := 0.0
	var thirty := 0.0
	for i in 60:
		sixty = Spatial.smooth_obstruction(sixty, 1.0, 1.0 / 60.0)
	for i in 30:
		thirty = Spatial.smooth_obstruction(thirty, 1.0, 1.0 / 30.0)
	t.near(sixty, thirty, 0.0001,
		"attack response is independent of FPS for 30 and 60 Hz")
	sixty = 1.0
	thirty = 1.0
	for i in 30:
		sixty = Spatial.smooth_obstruction(sixty, 0.0, 1.0 / 60.0)
	for i in 15:
		thirty = Spatial.smooth_obstruction(thirty, 0.0, 1.0 / 30.0)
	t.near(sixty, thirty, 0.0001,
		"release response is independent of FPS for 30 and 60 Hz")

	t.current = "bad network/physics values cannot break sound filtering"
	for invalid in [NAN, INF, -INF]:
		t.eq(Spatial.smooth_obstruction(0.25, invalid, 0.016), 0.25,
			"nonfinite obstacle target leaves current sound alone")
		t.eq(Spatial.smooth_obstruction(0.25, 0.5, invalid), 0.25,
			"nonfinite time step cannot inject NaN into sound mixer")
		t.eq(Spatial.smooth_obstruction(0.25, 0.5, 0.1, invalid), 0.25,
			"invalid attack time is ignored")
	t.eq(Spatial.smooth_obstruction(0.25, 0.5, -1.0), 0.25,
		"negative physics delta does not reverse sound transitions")
	t.check(Spatial.smooth_obstruction(0.0, 99.0, 0.1) <= 1.0,
		"high obstruction targets are clamped")
	t.check(Spatial.smooth_obstruction(1.0, -99.0, 0.1) >= 0.0,
		"negative obstruction targets are clamped")

	t.current = "native player and portable game mixer agree"
	var player := AudioStreamPlayer3D.new()
	if player.has_method("advance_obstruction_amount"):
		var reference := 0.0
		for i in 18:
			reference = Spatial.smooth_obstruction(reference, 1.0, 0.016)
			var native: float = player.call("advance_obstruction_amount", 1.0, 0.016)
			t.near(native, reference, 0.0015, "Cgame attack matches script fallback")
		for i in 25:
			reference = Spatial.smooth_obstruction(reference, 0.0, 0.016)
			var native: float = player.call("advance_obstruction_amount", 0.0, 0.016)
			t.near(native, reference, 0.0015, "Cgame release matches script fallback")
		t.near(float(player.call("get_obstruction_amount")), reference, 0.0015,
			"native player exposes the resulting real mixer setting")
	else:
		t.check(Spatial.smooth_obstruction(0.0, 1.0, 0.016) > 0.0,
			"stock Godot can reproduce the audio envelope without new native APIs")
	player.free()

	t.current = "live audio path retains bounded tracing and immediate first audio buffer"
	var source: String = (AudioScene as Script).source_code
	t.check(source.contains('player.has_method("advance_obstruction_amount")'),
		"real audio uses native smoothing when running on Cgame")
	t.check(source.contains('AudioSpatial.smooth_obstruction(old_amount, target, delta)'),
		"stock Godot supports the exact same physics-tick response")
	t.check(source.contains('if not native_smoothing:'),
		"Cgame does not double-apply its native obstruction state")
	t.check(source.contains('player.call("set_obstruction_amount", initial_obstruction)'),
		"first sound buffer is already correctly muffled by terrain")
	t.check(source.contains('OBSTRUCTION_RAYS_PER_TICK := 3'),
		"geometry ray budget remains limited to three per physics tick")
	t.check(source.contains('OBSTRUCTION_RECHECK_SECONDS := 0.25'),
		"occlusion rays remain time-sliced rather than running each mixer update")
