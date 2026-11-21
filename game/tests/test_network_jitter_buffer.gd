extends RefCounted
## Adaptive visual network clock is tested independently of the server or GPU.
const Jitter = preload("res://scripts/client/network_jitter_buffer.gd")
const EntityView = preload("res://scripts/client/entity_view.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func run(t) -> void:
	t.current = "stable 10Hz snapshots preserve minimal visual latency"
	var buffer = Jitter.new()
	buffer.observe(1.0, 10.0)
	for i in 60:
		buffer.observe(1.1 + float(i) * 0.1, 10.1 + float(i) * 0.1)
	t.near(buffer.delay, Jitter.BASE_DELAY, 0.0001,
		"stable arrivals do not add artificial network delay")
	var before: float = buffer.delay
	buffer.observe(7.1, 19.5) # A large local idle gap resets, not accumulates.
	t.near(buffer.delay, before, 0.0001,
		"return from a background pause keeps the minimal buffer")
	buffer.observe(7.1, 19.6)
	t.near(buffer.delay, before, 0.0001,
		"duplicated snapshot timestamps cannot simulate new packet jitter")

	t.current = "spikes expand the buffer quickly, quiet packets release slowly"
	buffer.reset()
	buffer.observe(1.0, 10.0)
	buffer.observe(1.1, 10.27)
	t.check(buffer.delay > Jitter.BASE_DELAY + 0.15,
		"late UDP arrival expands jitter history instead of freezing actors")
	t.check(buffer.delay <= Jitter.MAX_DELAY,
		"even severe jitter cannot cause unbounded presentation latency")
	var stretched: float = buffer.delay
	buffer.observe(1.1, 10.30)
	buffer.observe(1.1, 15.30) # Same server sample during a long outage.
	t.near(buffer.delay, stretched, 0.0001,
		"repeated render frames do not inflate or shrink the buffer")
	for i in 300:
		buffer.observe(1.2 + float(i) * 0.1, 10.37 + float(i) * 0.1)
	t.near(buffer.delay, Jitter.BASE_DELAY, 0.005,
		"a sustained stable connection returns to low latency")
	buffer.reset()
	buffer.observe(1.0, 10.0)
	buffer.observe(1.3, 10.3)
	t.check(buffer.delay > Jitter.BASE_DELAY,
		"missing an expected snapshot expands interpolation history")
	buffer.observe(0.9, 10.31)
	t.check(buffer.delay > Jitter.BASE_DELAY,
		"minor out-of-order server timestamps are ignored, not accepted")
	buffer.observe(0.2, 10.4)
	t.near(buffer.delay, Jitter.BASE_DELAY, 0.0001,
		"a new server epoch safely resets adaptive state")
	buffer.observe(NAN, 10.5)
	t.near(buffer.delay, Jitter.BASE_DELAY, 0.0001,
		"invalid incoming timestamps cannot poison buffer state")

	t.current = "packet-loss recovery hold does not mistake duplicates for arrivals"
	buffer.reset()
	t.eq(buffer.get_recovery_guard_packets(), 0,
		"legacy jitter adaptation starts without a hold")
	t.check(not buffer.set_recovery_guard_packets(-1),
		"negative recovery guard count rejected")
	t.check(not buffer.set_recovery_guard_packets(33),
		"excessive recovery guard count rejected")
	t.check(buffer.set_recovery_guard_packets(3),
		"game can require three genuine recovery snapshots")
	buffer.observe(1.0, 10.0)
	var loss_delay: float = buffer.observe(1.2, 10.2)
	t.check(loss_delay > Jitter.BASE_DELAY + 0.05,
		"missing a server tick expands interpolation reserve")
	t.eq(buffer.get_estimated_missing_snapshots(), 1,
		"missing snapshot estimate counts inferred 10Hz loss")
	t.eq(buffer.get_burst_loss_events(), 1,
		"one loss burst counted once")
	t.eq(buffer.get_recovery_hold_remaining(), 3,
		"loss arms three stable-arrival recovery credits")
	buffer.observe(1.2, 10.4)
	buffer.observe(1.1, 10.41)
	t.eq(buffer.get_recovery_hold_remaining(), 3,
		"duplicate and out-of-order packets cannot drain the hold")
	for i in 3:
		t.near(buffer.observe(1.3 + float(i) * 0.1, 10.3 + float(i) * 0.1),
			loss_delay, 0.000001,
			"good packet %d retains delay while recovery is guarded" % i)
	t.eq(buffer.get_recovery_hold_remaining(), 0,
		"three genuine arrivals exhaust the loss recovery guard")
	t.check(buffer.observe(1.6, 10.6) < loss_delay,
		"normal delay recovery resumes as soon as protection expires")
	buffer.reset()
	t.eq(buffer.get_recovery_guard_packets(), 3,
		"reset clears burst history but preserves opt-in policy")
	t.eq(buffer.get_estimated_missing_snapshots(), 0,
		"reset clears cumulative estimated missing snapshots")
	buffer.observe(1.0, 10.0)
	buffer.observe(1.1, 10.27)
	t.eq(buffer.get_estimated_missing_snapshots(), 0,
		"late but continuous server timestamps are not packet loss")
	buffer.observe(1.3, 10.47)
	t.eq(buffer.get_recovery_hold_remaining(), 3,
		"new missing tick arms another recovery guard")
	buffer.observe(2.0, 11.17)
	t.eq(buffer.get_recovery_hold_remaining(), 0,
		"reconnect gap clears old recovery state")
	t.check(buffer.set_recovery_guard_packets(0),
		"disable restores pre-existing release behavior")
	buffer.reset()

	t.current = "render time moves monotonically without future-packet prediction"
	var clock: float = Jitter.advance_clock(-1.0, 1.0, 0.12, 0.016)
	t.near(clock, 0.88, 0.00001, "first sample starts just behind server")
	var slow: float = Jitter.advance_clock(clock, 1.04, 0.3, 0.016)
	var fast: float = Jitter.advance_clock(clock, 1.2, 0.12, 0.016)
	t.check(slow >= clock, "growing buffer only slows motion, never rewinds actors")
	t.check(fast > slow, "network recovery permits gradual catchup")
	var latest: float = 1.0
	for i in 100:
		clock = Jitter.advance_clock(clock, latest, 0.12, 0.016)
		t.check(clock <= latest + 0.00001,
			"lost packets never cause speculative movement beyond the server")
	t.near(clock, latest, 0.00001, "visual clock eventually holds on a missing snapshot")
	t.near(Jitter.advance_clock(0.8, 1.0, 0.12, -1.0), 0.8, 0.00001,
		"paused game frames cannot rewind the clock")
	t.near(Jitter.advance_clock(0.8, 1.0, 0.12, INF), 0.8, 0.00001,
		"invalid frame delta cannot create a transform jump")
	t.near(Jitter.advance_clock(0.8, 0.2, 0.12, 0.016), 0.08, 0.00001,
		"a new server world resets clock to its authoritative epoch")

	t.current = "Cgame Node3D native method matches portable game clock"
	var host := Node3D.new()
	if host.has_method("advance_network_render_time"):
		for i in 60:
			var alpha: float = float(i) / 60.0
			var local: float = Jitter.advance_clock(1.0 + alpha, 1.7,
				0.13 + alpha * 0.08, 0.016)
			var native: float = Jitter.advance_clock(1.0 + alpha, 1.7,
				0.13 + alpha * 0.08, 0.016, host)
			t.near(native, local, 0.00001,
				"native Cgame and stock Godot fallback agree on the clock")
	else:
		t.check(is_finite(Jitter.advance_clock(0.8, 1.0, 0.12, 0.016)),
			"stock Godot supports the same safe fallback without a custom engine")
	host.free()
	var code: String = (EntityView as Script).source_code
	t.check(code.contains("_snapshot_buffer.observe(_snapshot_time,"),
		"live network arrival policy is integrated into the real entity renderer")
	t.check(code.contains("NetworkJitterBuffer.advance_clock("),
		"all simulated proxies share one monotone visual time source")
	t.check(code.contains("incoming_time < _snapshot_time"),
		"out-of-order snapshots cannot rewind the already rendered world")
	t.check(code.contains("history.clear() # A teleport"),
		"existing authoritative teleport discontinuity remains protected")

	t.current = "native Cgame adaptive jitter buffer matches GDScript on actual packet patterns"
	var local_policy := Jitter.new()
	var native_buffer: Object = null
	if ClassDB.class_exists("AdaptiveNetworkJitterBuffer"):
		native_buffer = ClassDB.instantiate("AdaptiveNetworkJitterBuffer")
		t.check(native_buffer != null and native_buffer.has_method("observe"),
			"native jitter buffer registered and callable")
		if native_buffer != null:
			t.check(native_buffer.configure(0.12, 0.35, 0.10),
				"Cgame network smoothing accepts the 10 Hz gameplay profile")
			t.check(local_policy.configure(0.12, 0.35, 0.10),
				"script and native use same policy parameters")
			t.check(native_buffer.set_recovery_guard_packets(3),
				"native network buffer enables loss-burst protection")
			t.check(local_policy.set_recovery_guard_packets(3),
				"script policy enables identical loss-burst protection")
			var rng := RandomNumberGenerator.new()
			rng.seed = 440321
			var server_ts := 1.0
			var arrival_ts := 20.0
			for i in 1200:
				# Normal, late and missing packets; backwards epochs and
				# repeated render frames all share the same input sequence.
				var mode: int = i % 47
				if mode == 3:
					arrival_ts += 0.19
				elif mode == 19:
					server_ts += 0.30
					arrival_ts += 0.32
				elif mode == 31:
					server_ts -= 0.25
					arrival_ts += 0.02
				elif mode == 41:
					arrival_ts += 2.5
				else:
					server_ts += 0.10
					arrival_ts += 0.10 + rng.randf_range(-0.025, 0.025)
				var script_delay: float = local_policy.observe(server_ts, arrival_ts)
				var engine_delay: float = float(native_buffer.observe(server_ts, arrival_ts))
				t.near(engine_delay, script_delay, 0.0000005,
					"packet delay parity sample %d" % i)
			var script_stats: Dictionary = local_policy.get_stats()
			var engine_stats: Dictionary = native_buffer.get_stats()
			for key in ["delay", "peak_jitter", "accepted_packets",
					"ignored_packets", "resets", "network_gaps",
					"expected_snapshot_step", "recovery_guard_packets",
					"recovery_hold_remaining", "estimated_missing_snapshots",
					"burst_loss_events"]:
				t.near(float(engine_stats[key]), float(script_stats[key]), 0.0000005,
					"native telemetry parity %s" % key)
			t.check(engine_stats["native_backend"], "native telemetry identifies backend")
			t.check(not script_stats["native_backend"], "portable telemetry identifies fallback")
			t.check(native_buffer.configure(0.06, 0.20, 0.05),
				"native buffer works with higher-rate 20 Hz games")
			t.check(local_policy.configure(0.06, 0.20, 0.05),
				"fallback works with higher-rate 20 Hz games")
			t.near(float(native_buffer.observe(1.0, 10.0)),
				local_policy.observe(1.0, 10.0), 0.0000005,
				"20 Hz initial sample")
			t.near(float(native_buffer.observe(1.05, 10.16)),
				local_policy.observe(1.05, 10.16), 0.0000005,
				"20 Hz late packet")

	t.current = "live EntityView selects native jitter adaptation when available"
	var live := EntityView.new()
	t.eq(live._snapshot_buffer.get_stats()["native_backend"],
		ClassDB.class_exists("AdaptiveNetworkJitterBuffer"),
		"player and infected render paths use the correct smoothing backend")
	t.check(live.network_jitter_stats().has("accepted_packets"),
		"game exposes local network diagnostics without server changes")
	t.eq(int(live.network_jitter_stats().get("recovery_guard_packets", 0)), 3,
		"Albion simulated proxies opt into 3-packet loss recovery")
	t.eq(live.network_missing_snapshot_estimate(), 0,
		"new presentation buffer has no inferred packet losses")
	t.eq(live.network_recovery_hold_remaining(), 0,
		"new presentation buffer has no unresolved loss hold")
	var online_source: String = FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(online_source.contains("Albion/NetworkEstimatedMissingSnapshots"),
		"game profiler exposes estimated missing snapshots")
	t.check(online_source.contains("Albion/NetworkRecoveryHoldRemaining"),
		"game profiler exposes current loss recovery pressure")
	t.near(float(live.network_jitter_stats()["expected_snapshot_step"]),
		1.0 / float(Defs.SNAPSHOT_RATE), 0.0000005,
		"client buffer tracks the real dedicated server snapshot rate")
	live.free()
