extends RefCounted
## Network condition simulator: latency, jitter, loss, duplication, reordering and a
## bandwidth cap (single FIFO link with a bounded queue), with a per-packet log and timeline.
##
## Concepts (not code) from Linux netem (delay/jitter/loss/duplicate/reorder) and the
## clumsy / Unity Network Simulator tools. Original GDScript; no third-party code copied, so no
## license obligations.
##
## Time unit: `now` and all *_at stamps are in SECONDS (float); latency/jitter are in ms.
## Deterministic: the same seed + same send sequence always yields the same log.
##
## Packet model: loss roll -> bandwidth queue (serialization delay, drop when the backlog
## exceeds max_queue_ms) -> delay = latency + uniform jitter in [-jitter, +jitter] (>= 0)
## -> optional reorder extra delay -> optional duplicate copy.

var latency_ms: float = 0.0
var jitter_ms: float = 0.0
var loss: float = 0.0
var duplicate: float = 0.0
var reorder: float = 0.0
var bandwidth_kbps: float = 0.0 # 0 = unlimited
var max_queue_ms: float = 1000.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _log: Array = []      # Array[Dictionary], index == packet id
var _pending: Array = []  # [{id, channel, bytes, sent_at, delivered_at}]
var _link_free: float = 0.0
var _max_delivered: float = -1.0


## Reject invalid diagnostic settings before they poison packet timing.
static func _finite_option(cfg: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get(key, fallback)
	if not (raw is float or raw is int):
		return fallback
	var number: float = float(raw)
	return number if is_finite(number) else fallback


func configure(cfg: Dictionary) -> void:
	latency_ms = maxf(0.0, _finite_option(cfg, "latency_ms", 0.0))
	jitter_ms = maxf(0.0, _finite_option(cfg, "jitter_ms", 0.0))
	loss = clampf(_finite_option(cfg, "loss", 0.0), 0.0, 1.0)
	duplicate = clampf(_finite_option(cfg, "duplicate", 0.0), 0.0, 1.0)
	reorder = clampf(_finite_option(cfg, "reorder", 0.0), 0.0, 1.0)
	bandwidth_kbps = maxf(0.0, _finite_option(cfg, "bandwidth_kbps", 0.0))
	max_queue_ms = maxf(1.0, _finite_option(cfg, "max_queue_ms", 1000.0))
	_rng.seed = int(cfg.get("seed", 1))
	_log.clear()
	_pending.clear()
	_link_free = 0.0
	_max_delivered = -1.0


## Submits a packet at time `now` (seconds). Returns its packet id.
func send(channel: Variant, bytes: PackedByteArray, now: float) -> int:
	var id: int = _log.size()
	var entry: Dictionary = {"id": id, "channel": channel, "size": bytes.size(), "sent_at": now,
		"delivered_at": -1.0, "dropped": false, "reason": "ok", "duplicated": false,
		"reordered": false, "base_ms": latency_ms, "jitter_ms": 0.0, "queue_ms": 0.0,
		"tx_ms": 0.0, "reorder_ms": 0.0}
	_log.append(entry)
	# Fixed roll order keeps the RNG stream aligned regardless of outcomes.
	var r_loss: float = _rng.randf()
	var r_jitter: float = _rng.randf_range(-1.0, 1.0)
	var r_reorder: float = _rng.randf()
	var r_dup: float = _rng.randf()
	var r_dup_jitter: float = _rng.randf_range(-1.0, 1.0)
	if r_loss < loss:
		entry["dropped"] = true
		entry["reason"] = "loss"
		return id
	var depart: float = now
	if bandwidth_kbps > 0.0:
		var backlog: float = maxf(0.0, _link_free - now)
		if backlog * 1000.0 > max_queue_ms:
			entry["dropped"] = true
			entry["reason"] = "bandwidth"
			return id
		var tx: float = float(bytes.size()) * 8.0 / (bandwidth_kbps * 1000.0)
		depart = now + backlog + tx
		_link_free = depart
		entry["queue_ms"] = backlog * 1000.0
		entry["tx_ms"] = tx * 1000.0
	var delay_ms: float = maxf(0.0, latency_ms + r_jitter * jitter_ms)
	entry["jitter_ms"] = delay_ms - latency_ms
	var extra_ms: float = 0.0
	if r_reorder < reorder:
		extra_ms = latency_ms + jitter_ms + 20.0
		entry["reordered"] = true
		entry["reorder_ms"] = extra_ms
	var at: float = depart + (delay_ms + extra_ms) / 1000.0
	entry["delivered_at"] = at
	if at < _max_delivered:
		entry["reordered"] = true # overtaken by an earlier-sent packet
	_max_delivered = maxf(_max_delivered, at)
	_pending.append({"id": id, "channel": channel, "bytes": bytes, "sent_at": now, "delivered_at": at})
	if r_dup < duplicate:
		entry["duplicated"] = true
		var dup_at: float = depart + maxf(0.0, latency_ms + r_dup_jitter * jitter_ms + 1.0) / 1000.0
		_pending.append({"id": id, "channel": channel, "bytes": bytes, "sent_at": now, "delivered_at": dup_at})
	return id


## Returns packets due by `now`, ordered by delivery time: {channel, bytes, sent_at, delivered_at, id}.
func receive(now: float) -> Array:
	var due: Array = []
	var rest: Array = []
	for p in _pending:
		if float((p as Dictionary)["delivered_at"]) <= now:
			due.append(p)
		else:
			rest.append(p)
	_pending = rest
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["delivered_at"] != b["delivered_at"]:
			return float(a["delivered_at"]) < float(b["delivered_at"])
		return int(a["id"]) < int(b["id"]))
	return due


func packet_count() -> int:
	return _log.size()


func packet(id: int) -> Dictionary:
	if id < 0 or id >= _log.size():
		return {}
	return (_log[id] as Dictionary).duplicate(true)


func pending_count() -> int:
	return _pending.size()


## Log entries whose send or delivery time falls in [t0, t1], ordered by send time.
func timeline(t0: float, t1: float) -> Array:
	var out: Array = []
	for e in _log:
		var d: Dictionary = e
		var s: float = d["sent_at"]
		var dl: float = d["delivered_at"]
		if (s >= t0 and s <= t1) or (dl >= 0.0 and dl >= t0 and dl <= t1):
			out.append(d.duplicate(true))
	return out


func stats() -> Dictionary:
	var sent: int = _log.size()
	var delivered: int = 0
	var lost: int = 0
	var bw_drop: int = 0
	var dups: int = 0
	var reord: int = 0
	var lats: Array = []
	var bytes_total: int = 0
	var first_sent: float = INF
	var last_at: float = 0.0
	for e in _log:
		var d: Dictionary = e
		first_sent = minf(first_sent, float(d["sent_at"]))
		if d["duplicated"]:
			dups += 1
		if d["reordered"]:
			reord += 1
		if d["dropped"]:
			if d["reason"] == "loss":
				lost += 1
			else:
				bw_drop += 1
			continue
		delivered += 1
		var at: float = d["delivered_at"]
		lats.append((at - float(d["sent_at"])) * 1000.0)
		bytes_total += int(d["size"])
		last_at = maxf(last_at, at)
	lats.sort()
	var avg: float = 0.0
	var p95: float = 0.0
	if not lats.is_empty():
		var sum: float = 0.0
		for v in lats:
			sum += float(v)
		avg = sum / float(lats.size())
		var idx: int = clampi(int(ceil(0.95 * float(lats.size()))) - 1, 0, lats.size() - 1)
		p95 = float(lats[idx])
	var span: float = last_at - first_sent if delivered > 0 else 0.0
	var thr: float = float(bytes_total) / span if span > 0.0 else 0.0
	return {"sent": sent, "delivered": delivered, "dropped": lost + bw_drop, "dropped_loss": lost,
		"dropped_bandwidth": bw_drop, "duplicated": dups, "reordered": reord,
		"avg_latency_ms": avg, "p95_latency_ms": p95, "throughput_bps": thr}


## Human-readable breakdown of why a packet took the time it did (or why it was dropped).
func delay_cause(packet_id: int) -> String:
	if packet_id < 0 or packet_id >= _log.size():
		return "unknown packet %d" % packet_id
	var d: Dictionary = _log[packet_id]
	if d["dropped"]:
		if d["reason"] == "loss":
			return "packet %d dropped by random loss (%.1f%%)" % [packet_id, loss * 100.0]
		return "packet %d dropped: bandwidth queue over %.0f ms at %.0f kbps" % [packet_id, max_queue_ms, bandwidth_kbps]
	var parts: Array[String] = ["base latency %.1f ms" % float(d["base_ms"])]
	var jit: float = d["jitter_ms"]
	if absf(jit) > 0.0005:
		parts.append("jitter %+.1f ms" % jit)
	var q: float = d["queue_ms"]
	if q > 0.0005:
		parts.append("queued %.1f ms behind bandwidth cap" % q)
	if float(d["tx_ms"]) > 0.0005:
		parts.append("serialization %.1f ms" % float(d["tx_ms"]))
	if float(d["reorder_ms"]) > 0.0005:
		parts.append("reorder hold %.1f ms" % float(d["reorder_ms"]))
	var total: float = (float(d["delivered_at"]) - float(d["sent_at"])) * 1000.0
	return "packet %d total %.1f ms = %s" % [packet_id, total, " + ".join(parts)]
