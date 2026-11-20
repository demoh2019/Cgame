extends RefCounted
## Camera and gameplay post-processing helpers (hit-stop, vignette, FOV kick, look-ahead, motion blur, letterbox).

const Fx = preload("res://scripts/client/camera_post_fx.gd")


func run(t) -> void:
	t.current = "damage and low health"
	t.check(Fx.hurt_intensity(2.0) >= 0.25, "a scratch still flashes")
	t.near(Fx.hurt_intensity(100.0), 1.0, 0.0001, "huge hits saturate")
	t.check(Fx.hurt_intensity(30.0) > Fx.hurt_intensity(10.0), "intensity grows with damage")
	t.near(Fx.low_health_amount(80.0), 0.0, 0.0001, "healthy has no desaturation")
	t.near(Fx.low_health_amount(0.0), 1.0, 0.0001, "death's door is full strength")
	t.near(Fx.low_health_amount(20.0), 0.5, 0.0001, "half way below the threshold")
	t.near(Fx.heartbeat(1.0, 0.0), 0.0, 0.0001, "no heartbeat when healthy")
	var peak := 0.0
	for i in 200:
		peak = maxf(peak, Fx.heartbeat(float(i) * 0.01, 1.0))
	t.check(peak > 0.9 and peak <= 1.0, "heartbeat peaks near full amount")
	t.check(Fx.decay(1.0, 0.5, 2.0) < Fx.decay(1.0, 0.1, 2.0), "decay is monotonic")

	t.current = "hit stop"
	t.eq(Fx.hit_stop(50.0, false, false), Vector2.ZERO, "others' hits never freeze you")
	t.eq(Fx.hit_stop(5.0, false, true), Vector2.ZERO, "light hits do not freeze")
	t.check(Fx.hit_stop(40.0, false, true).x > 0.0, "heavy hit freezes briefly")
	var kill := Fx.hit_stop(5.0, true, true)
	t.check(kill.x > 0.0 and kill.x < 0.2 and kill.y < 0.5, "kill hit-stop is short and slow-mo")
	t.check(Fx.stop_active(100, 200) and not Fx.stop_active(300, 200), "stop window expires")

	t.current = "speed feel"
	t.near(Fx.fov_target(38.0, false, false, 0.0), 38.0, 0.0001, "idle FOV unchanged")
	t.check(Fx.fov_target(38.0, true, false, 6.5) > 38.0, "sprint kicks FOV")
	t.check(Fx.fov_target(38.0, false, true, 9.0) > Fx.fov_target(38.0, true, false, 6.5), "bike kicks more")
	t.near(Fx.zoom_multiplier(false, false, 3.0), 1.0, 0.0001, "walking keeps zoom")
	t.check(Fx.zoom_multiplier(false, true, 9.0) > 1.1, "bike pulls out")
	t.eq(Fx.look_ahead(Vector2.ZERO, 5.0), Vector3.ZERO, "standing still has no look-ahead")
	var lead := Fx.look_ahead(Vector2(1, 0), 20.0)
	t.near(lead.length(), Fx.MAX_LOOK_AHEAD, 0.0001, "look-ahead capped")
	t.check(lead.x > 0.0 and lead.y == 0.0, "leads along move direction on the ground plane")
	t.near(Fx.radial_blur_amount(3.0, true, false, 3), 0.0, 0.0001, "no blur when slow")
	t.check(Fx.radial_blur_amount(9.0, false, true, 2) > 0.3, "bike at speed blurs")
	t.near(Fx.radial_blur_amount(9.0, false, true, 0), 0.0, 0.0001, "Low quality never blurs")
	t.near(Fx.radial_blur_amount(9.0, false, false, 3), 0.0, 0.0001, "walking never blurs")
	t.eq(Fx.blur_taps(0), 0, "Low has no taps")
	t.check(Fx.blur_taps(3) > Fx.blur_taps(1), "taps grow with quality")
	t.eq(Fx.blur_taps(9), Fx.blur_taps(3), "tier clamped")

	t.current = "letterbox and photo mode"
	t.eq(Fx.letterbox_target(true), 0.0, "alive: no bars")
	t.eq(Fx.letterbox_target(false), 1.0, "dead: bars in")
	var o := Fx.clamp_orbit(0.0, 5.0, 1000.0)
	t.near(o.y, 1.45, 0.0001, "pitch clamped")
	t.near(o.z, 45.0, 0.0001, "distance clamped")
	t.near(Fx.clamp_orbit(0.0, 0.0, 0.0).z, 4.0, 0.0001, "min distance")

	t.current = "overlay node"
	var node := Fx.new()
	var cam := Camera3D.new()
	node.setup(cam)
	t.check(node.get_child_count() == 1, "overlay layer created")
	node.update(0.016, {"health": 10.0, "alive": false}, Vector2.ZERO, 0.0, 2)
	t.check(node.get_child(0).get_child(0).visible, "overlay shown while dead or hurt")
	node.update(0.016, {"health": 100.0, "alive": true}, Vector2.ZERO, 0.0, 2)
	node.free()
	cam.free()
