extends RefCounted
## Snapshot delta compression, quantization and per-client baselines.

const SnapshotDelta = preload("res://scripts/shared/snapshot_delta.gd")
const NetQuantization = preload("res://scripts/shared/net_quantization.gd")
const SnapshotBaselines = preload("res://scripts/shared/snapshot_baselines.gd")


func _world(n: int) -> Dictionary:
	var w: Dictionary = {}
	for i in n:
		w[i] = {"pos": Vector3(i, 0.0, i * 2.0), "hp": 100, "yaw": 0.5, "tags": ["a", "b"], "meta": {"team": i % 3, "xs": [1, 2]}}
	return w


func run(t) -> void:
	t.current = "snapshot delta"
	var base: Dictionary = _world(5)
	var cur: Dictionary = base.duplicate(true)
	var e1: Dictionary = cur[1]
	e1["hp"] = 80
	e1["pos"] = Vector3(9, 9, 9)
	var meta2: Dictionary = (cur[2] as Dictionary)["meta"]
	(meta2["xs"] as Array).append(3)
	cur.erase(4)
	cur[10] = {"hp": 5, "pos": Vector3.ONE}
	(cur[0] as Dictionary).erase("tags")
	var d: Dictionary = SnapshotDelta.diff(base, cur)
	t.eq(SnapshotDelta.apply(base, d), cur, "round trip equals current")
	var changed: Dictionary = d["changed"]
	var ch1: Dictionary = changed[1]
	t.eq(ch1.size(), 2, "only changed fields present")
	t.check(not ch1.has("yaw"), "unchanged field omitted")
	t.check(not changed.has(3), "unchanged entity omitted")
	t.check((d["added"] as Dictionary).has(10), "new entity added")
	t.eq(d["removed"], PackedInt64Array([4]), "removed entity listed")
	t.eq(SnapshotDelta.apply(base, SnapshotDelta.diff(base, base)), base, "empty delta is identity")

	var base_copy: Dictionary = base.duplicate(true)
	var applied: Dictionary = SnapshotDelta.apply(base, d)
	(applied[3] as Dictionary)["hp"] = 1
	((applied[3] as Dictionary)["tags"] as Array).append("z")
	t.eq(base, base_copy, "baseline untouched by apply and result mutation")

	var f0: Dictionary = {1: {"x": 1.0, "y": 2.0}}
	var f1: Dictionary = {1: {"x": 1.004, "y": 2.5}}
	var fd: Dictionary = SnapshotDelta.diff(f0, f1, {"x": 0.01})
	var fch: Dictionary = (fd["changed"] as Dictionary)[1]
	t.check(not fch.has("x"), "jitter within tolerance suppressed")
	t.check(fch.has("y"), "field without tolerance resent")
	var fd2: Dictionary = SnapshotDelta.diff(f0, {1: {"x": 1.05, "y": 2.0}}, {"x": 0.01})
	t.check(((fd2["changed"] as Dictionary)[1] as Dictionary).has("x"), "change beyond tolerance resent")

	t.current = "quantization"
	for v in [-10.0, -3.3, 0.0, 0.123, 7.77, 10.0]:
		var q: int = NetQuantization.quantize_float(v, -10.0, 10.0, 12)
		var back: float = NetQuantization.dequantize_float(q, -10.0, 10.0, 12)
		var quantum: float = 20.0 / float((1 << 12) - 1)
		t.check(absf(back - v) <= quantum * 0.5 + 0.00001, "float error within half quantum %s" % v)
	t.eq(NetQuantization.quantize_float(99.0, 0.0, 1.0, 8), 255, "clamps high")
	t.eq(NetQuantization.quantize_float(-99.0, 0.0, 1.0, 8), 0, "clamps low")
	t.near(NetQuantization.dequantize_float(0, -5.0, 5.0, 8), -5.0, 0.0001, "min endpoint exact")
	t.near(NetQuantization.dequantize_float(255, -5.0, 5.0, 8), 5.0, 0.0001, "max endpoint exact")
	var qa: int = NetQuantization.quantize_angle(TAU + 1.0, 10)
	t.eq(qa, NetQuantization.quantize_angle(1.0, 10), "angle wraps past TAU")
	t.eq(NetQuantization.quantize_angle(-1.0, 10), NetQuantization.quantize_angle(TAU - 1.0, 10), "negative angle wraps")
	t.near(NetQuantization.dequantize_angle(qa, 10), 1.0, TAU / 1024.0 * 0.5 + 0.0001, "angle error within half quantum")
	t.eq(NetQuantization.quantize_angle(TAU - 0.0001, 8), 0, "angle just under TAU wraps to zero")
	var lo := Vector3(-100, 0, -100)
	var hi := Vector3(100, 50, 100)
	var vec := Vector3(12.5, 33.3, -77.7)
	var bytes: PackedByteArray = NetQuantization.pack_vector3(vec, lo, hi, 16)
	t.eq(bytes.size(), 6, "16 bits per axis is 6 bytes")
	var vb: Vector3 = NetQuantization.unpack_vector3(bytes, lo, hi, 16)
	t.check(absf(vb.x - vec.x) < 0.002 and absf(vb.y - vec.y) < 0.001 and absf(vb.z - vec.z) < 0.002, "vector round trip within quantum")
	var clamped: Vector3 = NetQuantization.unpack_vector3(NetQuantization.pack_vector3(Vector3(500, -9, 0), lo, hi, 10), lo, hi, 10)
	t.near(clamped.x, 100.0, 0.001, "vector clamps high axis")
	t.near(clamped.y, 0.0, 0.001, "vector clamps low axis")

	t.current = "snapshot baselines"
	var bl := SnapshotBaselines.new()
	var s1: Dictionary = _world(20)
	var p1: Dictionary = bl.build_packet(1, 1, s1)
	t.eq(p1["baseline"], -1, "first packet has no baseline")
	t.eq((p1["delta"]["added"] as Dictionary).size(), 20, "packet without ack is full")
	t.check(bl.baseline_for(1).is_empty(), "no baseline before ack")
	var s2: Dictionary = s1.duplicate(true)
	(s2[3] as Dictionary)["hp"] = 50
	var p2: Dictionary = bl.build_packet(1, 2, s2)
	t.eq(p2["baseline"], -1, "still full while nothing acked (lost packet)")
	bl.acknowledge(1, 2)
	t.eq(bl.baseline_for(1), s2, "ack sets baseline to that snapshot")
	var client_baseline: Dictionary = bl.baseline_for(1)
	(client_baseline[3] as Dictionary)["hp"] = -900
	((client_baseline[3] as Dictionary)["tags"] as Array).append("external_mutation")
	t.eq(bl.baseline_for(1), s2,
		"reading a baseline returns a deep copy and cannot corrupt pending deltas")
	var s3: Dictionary = s2.duplicate(true)
	(s3[4] as Dictionary)["hp"] = 10
	var p3: Dictionary = bl.build_packet(1, 3, s3)
	t.eq(p3["baseline"], 2, "baseline is acked sequence")
	t.eq((p3["delta"]["added"] as Dictionary).size(), 0, "after ack only deltas")
	t.eq((p3["delta"]["changed"] as Dictionary).size(), 1, "delta has just the change")
	var s4: Dictionary = s3.duplicate(true)
	(s4[5] as Dictionary)["hp"] = 11
	var p4: Dictionary = bl.build_packet(1, 4, s4)
	t.eq(p4["baseline"], 2, "lost packet 3 keeps old baseline")
	t.eq(SnapshotDelta.apply(bl.baseline_for(1), p4["delta"]), s4, "client rebuilds from old baseline")
	bl.acknowledge(1, 1)
	t.eq(bl.baseline_for(1), s2, "stale ack ignored")
	bl.acknowledge(1, 999)
	t.eq(bl.baseline_for(1), s2, "unknown ack ignored")
	bl.forget(1)
	t.check(bl.baseline_for(1).is_empty(), "forget clears baseline")

	t.current = "snapshot IDs are immutable across retries and late sends"
	var replay := SnapshotBaselines.new()
	replay.record_sent(42, 5, {"unit": {"hp": 80}})
	replay.record_sent(42, 5, {"unit": {"hp": 1}})
	replay.acknowledge(42, 5)
	t.eq((replay.baseline_for(42)["unit"] as Dictionary)["hp"], 80,
		"same sequence keeps the original delivered snapshot")
	replay.record_sent(42, 5, {"unit": {"hp": 1}})
	replay.record_sent(42, 4, {"unit": {"hp": 1}})
	var replay_pending: Dictionary = (replay._clients[42] as Dictionary)["pending"]
	t.eq(replay_pending.size(), 0, "acked and older snapshot IDs cannot re-enter history")
	replay.record_sent(42, 6, {"unit": {"hp": 60}})
	replay.acknowledge(42, 6)
	t.eq((replay.baseline_for(42)["unit"] as Dictionary)["hp"], 60,
		"newer sequence is still acknowledged and applied normally")
	var retry := SnapshotBaselines.new()
	var sent: Dictionary = retry.build_packet(8, 7, {1: {"hp": 30}})
	var resent: Dictionary = retry.build_packet(8, 7, {1: {"hp": 1}})
	t.eq(resent["delta"], sent["delta"],
		"retrying the same sequence retransmits identical world state")
	retry.acknowledge(8, 7)
	t.eq((retry.baseline_for(8)[1] as Dictionary)["hp"], 30,
		"acknowledged baseline matches both copies of the retried packet")

	var bl2 := SnapshotBaselines.new()
	for i in 100:
		bl2.record_sent(7, i, {i: {"v": i}})
	bl2.acknowledge(7, 10)
	t.check(bl2.baseline_for(7).is_empty(), "old snapshot evicted so its ack is ignored")
	bl2.acknowledge(7, 99)
	t.check(bl2.baseline_for(7).has(99), "recent snapshot still ackable")
	var bl3 := SnapshotBaselines.new()
	for i in 100:
		bl3.record_sent(7, i, {})
	var pend: Dictionary = (bl3._clients[7] as Dictionary)["pending"]
	t.check(pend.size() <= 32, "history bounded to 32")

	t.current = "out-of-order send history keeps newer snapshot ACKs"
	var reordered := SnapshotBaselines.new()
	reordered.record_sent(55, 100, {1: {"hp": 100}})
	for sequence in range(1, 70):
		reordered.record_sent(55, sequence, {1: {"hp": sequence}})
	var out_of_order_pending: Dictionary = (reordered._clients[55] as Dictionary)["pending"]
	t.eq(out_of_order_pending.size(), SnapshotBaselines.MAX_UNACKED,
		"out-of-order sends keep a strict 32-snapshot memory window")
	t.check(out_of_order_pending.has(100),
		"late older transmissions cannot evict the newest snapshot")
	t.check(not out_of_order_pending.has(1),
		"old sequence IDs are evicted regardless of arrival order")
	reordered.acknowledge(55, 50)
	t.eq((reordered.baseline_for(55)[1] as Dictionary)["hp"], 50,
		"late valid ACK can select a retained older state")
	reordered.acknowledge(55, 100)
	t.eq((reordered.baseline_for(55)[1] as Dictionary)["hp"], 100,
		"later ACK advances to newest state without rollback")
	reordered.record_sent(55, 70, {1: {"hp": -70}})
	t.eq(reordered.baseline_for(55)[1]["hp"], 100,
		"replayed older sequence cannot replace acknowledged state")

	t.current = "compression size"
	var big: Dictionary = _world(200)
	var nxt: Dictionary = big.duplicate(true)
	for i in 5:
		(nxt[i * 7] as Dictionary)["hp"] = 42
	var dd: Dictionary = SnapshotDelta.diff(big, nxt)
	var full_size: int = var_to_bytes(nxt).size()
	var delta_size: int = var_to_bytes(dd).size()
	t.check(delta_size * 10 < full_size, "delta far smaller than full (%d vs %d)" % [delta_size, full_size])
	t.eq(SnapshotDelta.apply(big, dd), nxt, "large state round trip")
