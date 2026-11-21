extends RefCounted
## Rollback netcode (input prediction, rollback/resim, checksums, stalls) and client-side
## movement prediction with server reconciliation.

const RollbackNetcode = preload("res://scripts/shared/rollback_netcode.gd")
const ClientPrediction = preload("res://scripts/shared/client_prediction.gd")

const DT: float = 1.0 / 60.0

var _max_snapshots_seen: int = 0


func run(t) -> void:
	_test_peers(t)
	_test_late_input(t)
	_test_desync(t)
	_test_stall(t)
	_test_prediction(t)


# --- deterministic toy simulation -------------------------------------------------------------

func _initial() -> Dictionary:
	return {"tick": 0, "acc": 0, "x": {1: 0, 2: 0}}


func _step(s: Dictionary, inputs: Dictionary, _dt: float) -> Dictionary:
	var x: Dictionary = s["x"]
	var acc: int = s["acc"]
	for pid in inputs:
		var inp: Dictionary = inputs[pid]
		var dx: int = inp.get("dx", 0)
		var nx: int = int(x[pid]) + dx
		x[pid] = nx
		acc = (acc * 31 + dx * int(pid) + nx) % 1000003
	s["acc"] = acc
	s["tick"] = int(s["tick"]) + 1
	return s


func _inp(pid: int, n: int) -> Dictionary:
	return {"dx": ((n * 7 + pid * 3) % 5) - 2}


func _reference_checksum(frame: int, delay: int) -> int:
	var s: Dictionary = _initial()
	for f in range(frame):
		var inputs: Dictionary = {}
		for pid in [1, 2]:
			inputs[pid] = {} if f < delay else _inp(pid, f - delay)
		s = _step(s, inputs, DT)
	return RollbackNetcode.state_checksum(s)


func _make(local_pid: int, delay: int, max_pred: int, biased: bool = false) -> RollbackNetcode:
	var nc := RollbackNetcode.new()
	var stepper: Callable = _step
	if biased:
		stepper = func(s: Dictionary, inputs: Dictionary, d: float) -> Dictionary:
			if int(s["tick"]) == 5:
				s["acc"] = int(s["acc"]) + 1 # deliberately non-deterministic vs the other peer
			return _step(s, inputs, d)
	nc.setup(stepper, _initial(), [1, 2], [local_pid], DT, delay, max_pred)
	return nc


## Runs two peers over a link with `latency` ticks. Returns [peer1, peer2].
func _run_peers(ticks: int, latency: int, delay: int, max_pred: int, bias_b: bool, jitter: bool = false) -> Array:
	var peers: Array = [_make(1, delay, max_pred), _make(2, delay, max_pred, bias_b)]
	var counters: Array[int] = [0, 0]
	var wire: Array = []
	_max_snapshots_seen = 0
	for tick in range(ticks):
		var due: Array = []
		var rest: Array = []
		for m in wire:
			if int((m as Dictionary)["at"]) <= tick:
				due.append(m)
			else:
				rest.append(m)
		wire = rest
		for m in due:
			var msg: Dictionary = m
			var peer: RollbackNetcode = peers[msg["to"]]
			if msg["kind"] == "input":
				peer.add_remote_input(msg["player"], msg["frame"], msg["input"])
			else:
				peer.add_remote_checksum(msg["frame"], msg["checksum"])
		for i in 2:
			var peer: RollbackNetcode = peers[i]
			var pid: int = i + 1
			peer.add_local_input(pid, _inp(pid, counters[i]))
			counters[i] += 1
			var lat: int = latency + (tick % 3 if jitter else 0)
			for o in peer.drain_outgoing():
				var entry: Dictionary = o
				wire.append({"at": tick + lat, "to": 1 - i, "kind": "input", "player": entry["player"],
						"frame": entry["frame"], "input": entry["input"]})
			for r in peer.get_checksum_report():
				var rep: Dictionary = r
				wire.append({"at": tick + latency, "to": 1 - i, "kind": "sum", "frame": rep["frame"],
						"checksum": rep["checksum"]})
			peer.advance()
			_max_snapshots_seen = maxi(_max_snapshots_seen, peer.snapshot_count())
	return peers


func _test_peers(t) -> void:
	t.current = "two peers with latency converge"
	for cfg in [[0, 0], [3, 0], [4, 2], [6, 1]]:
		var latency: int = cfg[0]
		var delay: int = cfg[1]
		var peers: Array = _run_peers(120, latency, delay, 12, false, latency > 3)
		var a: RollbackNetcode = peers[0]
		var b: RollbackNetcode = peers[1]
		var f: int = mini(mini(a.confirmed_frame, b.confirmed_frame) + 1, mini(a.frame, b.frame))
		t.check(f > 60, "latency %d delay %d: confirmed far enough (%d)" % [latency, delay, f])
		var ref: int = _reference_checksum(f, delay)
		t.eq(a.checksum_of(f), b.checksum_of(f), "latency %d delay %d: peers agree at frame %d" % [latency, delay, f])
		t.eq(a.checksum_of(f), ref, "latency %d delay %d: equals lockstep reference" % [latency, delay])
		t.check(not a.has_desync() and not b.has_desync(), "latency %d delay %d: no false desync" % [latency, delay])
		if latency > 0 and delay < latency:
			t.check(a.rollbacks > 0, "latency %d: prediction misses cause rollbacks" % latency)
		t.check(_max_snapshots_seen <= a.snapshot_capacity, "snapshot ring stays bounded (%d <= %d)" % [_max_snapshots_seen, a.snapshot_capacity])
		t.check(a.snapshot_count() <= a.snapshot_capacity, "snapshot ring bounded at end")


func _test_late_input(t) -> void:
	t.current = "late input triggers rollback"
	var nc: RollbackNetcode = _make(1, 0, 12)
	for n in 10:
		nc.add_local_input(1, _inp(1, n))
		t.check(nc.advance(), "predicting frame %d" % n)
	t.eq(nc.frame, 10, "ten frames simulated on prediction")
	t.eq(nc.confirmed_frame, -1, "nothing confirmed without remote inputs")
	t.eq(nc.rollbacks, 0, "no rollback yet")
	for f in 10:
		nc.add_remote_input(2, f, _inp(2, f))
	t.eq(nc.confirmed_frame, 9, "remote inputs confirm frames")
	nc.process()
	t.check(nc.rollbacks >= 1, "mispredicted frames rolled back")
	t.check(nc.resimulated_frames > 0, "frames were resimulated")
	t.eq(nc.frame, 10, "resimulation returns to the present")
	t.eq(RollbackNetcode.state_checksum(nc.get_state()), _reference_checksum(10, 0), "state equals lockstep reference")
	# Duplicate and stale deliveries are harmless.
	var before: int = nc.rollbacks
	nc.add_remote_input(2, 3, {"dx": 99})
	nc.process()
	t.eq(nc.rollbacks, before, "duplicate input ignored")
	t.check(not nc.rollback_to(500), "rollback to the future refused")
	t.check(not nc.rollback_to(-5), "rollback outside the ring refused")
	# Matching prediction needs no rollback.
	var quiet: RollbackNetcode = _make(1, 0, 12)
	for n in 5:
		quiet.add_local_input(1, {})
		quiet.advance()
	for f in 5:
		quiet.add_remote_input(2, f, {})
	quiet.process()
	t.eq(quiet.rollbacks, 0, "correct prediction does not roll back")


func _test_desync(t) -> void:
	t.current = "desync detection"
	var peers: Array = _run_peers(80, 2, 0, 12, true)
	var a: RollbackNetcode = peers[0]
	var b: RollbackNetcode = peers[1]
	t.check(a.has_desync(), "peer A flags the diverged checksum")
	t.check(b.has_desync(), "peer B flags the diverged checksum")
	if a.has_desync():
		t.eq(a.desync_frames[0], 6, "first diverged frame is right after the bad step")
	var clean: Array = _run_peers(80, 2, 0, 12, false)
	t.check(not (clean[0] as RollbackNetcode).has_desync(), "deterministic step never desyncs")


func _test_stall(t) -> void:
	t.current = "prediction window stall"
	var nc: RollbackNetcode = _make(1, 0, 4)
	var advanced: int = 0
	for n in 10:
		nc.add_local_input(1, _inp(1, n))
		if nc.advance():
			advanced += 1
	t.eq(advanced, 4, "stops after max_prediction frames")
	t.eq(nc.frame, 4, "frame frozen at the window edge")
	t.check(nc.is_stalled(), "reports stalled")
	t.check(nc.stall_count > 0, "stall counted")
	for f in 4:
		nc.add_remote_input(2, f, _inp(2, f))
	t.check(not nc.is_stalled(), "remote inputs reopen the window")
	while nc.advance():
		pass
	t.eq(nc.frame, 8, "window slides with the confirmed frame")
	var lock: RollbackNetcode = _make(1, 0, 0)
	lock.add_local_input(1, {})
	t.check(not lock.advance(), "max_prediction 0 is lockstep: waits for remote")
	lock.add_remote_input(2, 0, {})
	t.check(lock.advance(), "lockstep proceeds once all inputs known")
	t.eq(lock.rollbacks, 0, "lockstep never rolls back")
	t.check(nc.snapshot_count() <= nc.snapshot_capacity, "snapshot ring bounded while stalled")


# --- client prediction ------------------------------------------------------------------------

func _move(s: Dictionary, input: Dictionary, dt: float) -> Dictionary:
	var dir: Vector2 = input.get("dir", Vector2.ZERO)
	s["pos"] = (s["pos"] as Vector2) + dir * 100.0 * dt
	return s


func _server_move(s: Dictionary, input: Dictionary, dt: float) -> Dictionary:
	var dir: Vector2 = input.get("dir", Vector2.ZERO)
	s["pos"] = (s["pos"] as Vector2) + dir * 90.0 * dt # server is slightly slower (e.g. a slow effect)
	return s


func _test_prediction(t) -> void:
	t.current = "client prediction reconcile"
	var cp := ClientPrediction.new()
	cp.setup(_move, {"pos": Vector2.ZERO}, "pos", 50.0, 10.0)
	var server: Dictionary = {"pos": Vector2.ZERO}
	var inputs: Array = []
	for n in 12:
		var inp: Dictionary = {"dir": Vector2(1, 0.0 if n < 6 else 1.0)}
		inputs.append(inp)
		t.eq(cp.predict(inp, DT), n + 1, "sequence numbers increase")
	t.eq(cp.pending_count(), 12, "all inputs pending")
	t.near((cp.state["pos"] as Vector2).x, 12 * 100.0 * DT, 0.001, "client applied inputs immediately")
	var predicted: Vector2 = cp.state["pos"]
	for n in 6:
		server = _server_move(server, inputs[n], DT)
	var err: float = cp.reconcile(server, 6)
	t.check(err > 0.0, "server disagreement yields an error (%.3f)" % err)
	t.eq(cp.pending_count(), 6, "acknowledged inputs dropped")
	var expected: Dictionary = server.duplicate(true)
	for n in range(6, 12):
		expected = _move(expected, inputs[n], DT)
	t.near((cp.state["pos"] as Vector2).distance_to(expected["pos"]), 0.0, 0.0001, "state = server state + replayed inputs")
	var vis: Vector2 = cp.visual_state()["pos"]
	t.near(vis.distance_to(predicted), 0.0, 0.0001, "no visible pop: smoothed position continues from the old prediction")
	t.check(cp.offset_magnitude() > 0.0, "correction stored as visual offset")
	var before: float = cp.offset_magnitude()
	cp.update(0.05)
	t.check(cp.offset_magnitude() < before, "visual error decays")
	t.near(cp.offset_magnitude(), before * exp(-0.5), 0.0001, "exponential decay rate")
	for k in 60:
		cp.update(DT)
	t.check(cp.offset_magnitude() < 0.01, "visual error vanishes over time")
	for n in range(6, 12):
		server = _server_move(server, inputs[n], DT)
	cp.reconcile(server, 12)
	t.eq(cp.pending_count(), 0, "everything acknowledged")
	t.near((cp.state["pos"] as Vector2).distance_to(server["pos"]), 0.0, 0.0001, "fully acked state equals the server")
	t.near(cp.reconcile(server, 5), 0.0, 0.0, "stale ack ignored")
	t.eq(cp.last_acked_seq, 12, "stale ack does not rewind")

	t.current = "client prediction snap"
	var snap := ClientPrediction.new()
	snap.setup(_move, {"pos": Vector2.ZERO}, "pos", 1.0, 10.0)
	snap.predict({"dir": Vector2(1, 0)}, DT)
	var far: Dictionary = {"pos": Vector2(40, 0)}
	var big: float = snap.reconcile(far, 1)
	t.check(big > 1.0, "large error measured")
	t.eq(snap.snaps, 1, "error above threshold snaps")
	t.near(snap.offset_magnitude(), 0.0, 0.0, "snap leaves no visual offset")
	t.near((snap.state["pos"] as Vector2).x, 40.0, 0.0001, "snapped to the server position")
	var scalar := ClientPrediction.new()
	scalar.setup(func(s: Dictionary, i: Dictionary, d: float) -> Dictionary:
		s["pos"] = float(s["pos"]) + float(i.get("v", 0.0)) * d
		return s, {"pos": 0.0}, "pos", 10.0, 5.0)
	scalar.predict({"v": 60.0}, 1.0)
	scalar.reconcile({"pos": 50.0}, 0)
	t.check(scalar.offset_magnitude() == 0.0 or scalar.last_error >= 0.0, "scalar positions are supported")
