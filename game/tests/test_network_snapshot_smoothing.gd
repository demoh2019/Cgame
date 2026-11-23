extends RefCounted
## Monotonic, visual-only snapshot Hermite smoothing with native and stock parity.
const Smooth = preload("res://scripts/client/network_snapshot_smoothing.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")


func run(t) -> void:
	t.current = "two snapshots preserve old linear interpolation"
	var a: Array = [1.0, Vector3(0, 1, 0), 0.0]
	var b: Array = [1.1, Vector3(4, 3, 2), 0.4]
	for i in 21:
		var alpha: float = float(i) / 20.0
		var linear: Vector3 = (a[1] as Vector3).lerp(b[1], alpha)
		var value: Vector3 = Smooth.sample_position([], a, b, [], alpha)
		t.check(value.distance_to(linear) < 0.0001,
			"two-snapshot fallback exactly reproduces prior linear path")
	t.eq(Smooth.sample_position([], a, b, [], 0.0), a[1],
		"older server pose is preserved exactly")
	t.eq(Smooth.sample_position([], a, b, [], 1.0), b[1],
		"newest server pose is preserved exactly")

	t.current = "velocity-sensitive cubic motion with no overshoot"
	var start := Vector3.ZERO
	var finish := Vector3(4, 2, 1)
	var eased: Vector3 = Smooth.hermite(start, finish, Vector3(20, 20, 0),
		Vector3.ZERO, 0.1, 0.5)
	t.check(eased.x > 2.0 and eased.x < 4.0,
		"estimated velocity changes the midpoint from a fixed-speed lerp")
	for i in 101:
		var k: float = float(i) / 100.0
		var pose: Vector3 = Smooth.hermite(start, finish,
			Vector3(100, -50, 20), Vector3(-200, 40, 100), 0.1, k)
		t.check(pose.x >= start.x - 0.0001 and pose.x <= finish.x + 0.0001,
			"x never overshoots authoritative positions")
		t.check(pose.y >= start.y - 0.0001 and pose.y <= finish.y + 0.0001,
			"y never overshoots stairs or ground")
		t.check(pose.z >= start.z - 0.0001 and pose.z <= finish.z + 0.0001,
			"z never slides around an obstacle")
	var previous: Array = [0.9, Vector3(-1, 1, 0), 0.0]
	var following: Array = [1.2, Vector3(4.4, 3, 2), 0.4]
	var with_history: Vector3 = Smooth.sample_position(
		previous, a, b, following, 0.5)
	t.check(with_history.is_finite(), "neighbor velocity interpolation remains finite")
	t.check(with_history.x >= 0.0 and with_history.x <= 4.0,
		"neighboring snapshots cannot create a false collision shortcut")

	t.current = "packet loss, stalls and teleports retain safe fallbacks"
	var far: Vector3 = Vector3(20, 0, 0)
	t.eq(Smooth.hermite(start, far, Vector3.ONE, Vector3.ONE, 0.1, 0.5),
		Vector3(10, 0, 0), "teleport-length segment falls back to linear motion")
	t.eq(Smooth.hermite(start, finish, Vector3.ONE, Vector3.ONE, 0.0, 0.5),
		start.lerp(finish, 0.5), "duplicate timestamp retains linear fallback")
	t.eq(Smooth.hermite(start, finish, Vector3.ONE, Vector3.ONE, 1.0, 0.5),
		start.lerp(finish, 0.5), "large network gap cannot create a wild curve")
	t.eq(Smooth.hermite(start, finish, Vector3.INF, Vector3.ONE, 0.1, 0.5),
		start.lerp(finish, 0.5), "invalid velocities cannot affect transforms")
	t.eq(Smooth.hermite(start, finish, Vector3.ONE, Vector3.ONE, 0.1, -20.0),
		start, "extrapolation before the first snapshot is clamped")
	t.eq(Smooth.hermite(start, finish, Vector3.ONE, Vector3.ONE, 0.1, 20.0),
		finish, "missing future packets cannot extrapolate beyond server pose")
	t.eq(Smooth.hermite(Vector3.INF, finish, Vector3.ONE,
		Vector3.ONE, 0.1, 0.5), finish,
		"invalid server position never propagates NaNs into render transforms")
	t.eq(Smooth.hermite(start, Vector3.INF, Vector3.ONE,
		Vector3.ONE, 0.1, 0.5), start,
		"invalid target falls back to the last valid server position")

	t.current = "malformed snapshots cannot corrupt visual entity transforms"
	t.eq(Smooth.sample_position([], [1.0, start], [1.0, Vector3.INF], [], 0.5),
		start, "duplicate timestamp with invalid destination stays finite")
	t.eq(Smooth.sample_position([], [1.0, Vector3.INF], [0.5, finish], [], 0.5),
		finish, "out-of-order timestamp with invalid source uses valid destination")
	t.eq(Smooth.sample_position([], [], b, [], 0.5), Vector3.ZERO,
		"missing source position cannot trigger an out-of-range array access")
	t.eq(Smooth.sample_position([], [1.0, start], [1.1, "not-a-position"], [], 0.5),
		Vector3.ZERO, "bad position type cannot crash snapshot interpolation")
	t.eq(Smooth.sample_position([], ["bad-time", start], b, [], 0.5),
		b[1], "nonnumeric snapshot timestamp uses latest authoritative position")
	t.eq(Smooth.sample_position([], [NAN, start], b, [], 0.5),
		b[1], "nonfinite snapshot time uses latest authoritative position")
	t.check(Smooth.sample_position(["bad-time", "bad-position"],
		a, b, ["bad-time", "bad-position"], 0.5).is_finite(),
		"malformed velocity neighbors cannot poison a valid network segment")

	t.current = "native Godot engine and stock fallback agree"
	var host := Node3D.new()
	if host.has_method("interpolate_network_snapshot"):
		for i in 41:
			var k: float = float(i) / 40.0
			var source: Vector3 = Smooth.hermite(start, finish,
				Vector3(19, 2, 3), Vector3(3, 18, 5), 0.1, k)
			var native: Vector3 = Smooth.hermite(start, finish,
				Vector3(19, 2, 3), Vector3(3, 18, 5), 0.1, k, host)
			t.check(source.distance_to(native) < 0.0002,
				"native and GDScript cubic produce the same silhouette")
	else:
		t.check(Smooth.hermite(start, finish, Vector3(19, 2, 3),
			Vector3(3, 18, 5), 0.1, 0.5).is_finite(),
			"stock Godot uses reliable pure GDScript fallback")
	host.free()

	t.current = "actual world entities use buffered network smoothing"
	var code: String = (EntityView as Script).source_code
	t.check(code.contains("SnapshotSmoothing.sample_position("),
		"networked players and zombies use the new cubic smoother")
	t.check(code.contains("if GraphicsQuality.level() == 0:"),
		"Performance keeps cheap linear sampling without extra history reads")
	t.check(code.contains("history[i - 2] if i >= 2 else []") and
		code.contains("history[i + 1] if i + 1 < history.size() else []"),
		"historical neighbor snapshots feed the endpoint velocities")
	t.check(code.contains("history.clear() # A teleport"),
		"server teleports still reset visual history")
	t.check(code.contains("INTERPOLATION_DELAY := 0.12"),
		"existing server jitter buffer remains authoritative")
	t.check(code.contains("lerp_angle(float(older[2]), float(newer[2]), k)"),
		"facing rotation retains its trusted shortest-path interpolation")
	t.check(code.contains("if _render_time >= float(older[0]):"),
		"source never predicts missing future server snapshots")
