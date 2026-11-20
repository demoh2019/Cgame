extends RefCounted
## Animation LOD fallback (update intervals, delta accumulation, registration) and engine feature helpers.

const AnimLod = preload("res://scripts/client/anim_lod.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")


func run(t) -> void:
	t.current = "update interval"
	t.eq(AnimLod.update_interval(5.0, true), 1, "close: every frame")
	t.eq(AnimLod.update_interval(15.0, true), 2, "boundary moves to the next tier")
	t.eq(AnimLod.update_interval(20.0, true), 2, "mid: every 2nd frame")
	t.eq(AnimLod.update_interval(50.0, true), 4, "far: every 4th frame")
	t.eq(AnimLod.update_interval(70.0, true), 0, "beyond far: paused")
	t.eq(AnimLod.update_interval(2.0, false), 0, "off-screen: paused")
	t.eq(AnimLod.update_interval(20.0, true, 30.0, 60.0, 90.0), 1, "custom thresholds")

	t.current = "quality scale"
	t.check(AnimLod.distance_scale(0) < AnimLod.distance_scale(3), "Ultra keeps full-rate animation farther")
	t.near(AnimLod.distance_scale(99), AnimLod.distance_scale(3), 0.0001, "level clamped high")
	t.near(AnimLod.distance_scale(-4), AnimLod.distance_scale(0), 0.0001, "level clamped low")

	t.current = "delta accumulation"
	for interval in [1, 2, 4]:
		var accumulated := 0.0
		var advanced := 0.0
		var steps := 0
		for frame in range(1, 41):
			var result := AnimLod.tick(accumulated, 0.016, interval, frame, 1)
			accumulated = result[0]
			if float(result[1]) >= 0.0:
				advanced += float(result[1])
				steps += 1
		t.near(advanced + accumulated, 40 * 0.016, 0.0001, "no animation time lost at interval %d" % interval)
		t.check(steps <= int(ceil(40.0 / interval)) + 1, "fewer advances at interval %d" % interval)
	var paused := AnimLod.tick(0.05, 0.016, 0, 3, 0)
	t.near(float(paused[0]), 0.05, 0.0001, "paused keeps its accumulator")
	t.check(float(paused[1]) < 0.0, "paused never advances")
	var capped := AnimLod.tick(0.49, 1.0, 4, 3, 0)
	t.check(float(capped[1]) <= AnimLod.MAX_ACCUMULATED + 0.0001 or float(capped[0]) <= AnimLod.MAX_ACCUMULATED, "catch-up capped")

	t.current = "registration"
	var lod := AnimLod.new()
	var model := Node3D.new()
	var animator := AnimationPlayer.new()
	model.add_child(animator)
	lod.register(animator, model)
	lod.register(animator, model)
	t.eq(lod.count(), 1, "registered once")
	t.eq(animator.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "animator in manual mode")
	lod.unregister(animator)
	t.eq(lod.count(), 0, "unregistered")
	t.eq(animator.callback_mode_process, AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE, "mode restored")
	lod.free()
	model.free()

	t.current = "engine features"
	t.check(not EngineFeatures.has("NoSuchEngineClassXyz"), "unknown class absent")
	t.check(EngineFeatures.has("Node3D"), "known class present")
	var node := Node.new()
	EngineFeatures.tag_node(node, ["Player"])
	t.check(node.has_meta("tags") == EngineFeatures.has("GameplayTagContainer"), "tags only with native support")
	node.free()
