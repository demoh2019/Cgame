extends RefCounted
## Deterministic CPU frame pacing summaries for screenshot/demo GPU research.
## Frame samples are process-delta milliseconds; these are not GPU timer queries.
## Discard invalid warmup/stall values explicitly instead of faking high FPS.

const MAX_VALID_FRAME_MS := 1000.0


static func _percentile(sorted: Array[float], share: float) -> float:
	if sorted.is_empty():
		return 0.0
	var place: float = clampf(share, 0.0, 1.0) * float(sorted.size() - 1)
	var low: int = floori(place)
	var high: int = mini(low + 1, sorted.size() - 1)
	return lerpf(sorted[low], sorted[high], place - float(low))


static func summarize(samples: Array[float]) -> Dictionary:
	var cleaned: Array[float] = []
	for ms in samples:
		if is_finite(ms) and ms > 0.0 and ms <= MAX_VALID_FRAME_MS:
			cleaned.append(ms)
	if cleaned.is_empty():
		return {"count": 0, "p50_ms": 0.0, "p95_ms": 0.0,
			"p99_ms": 0.0, "mean_ms": 0.0, "one_percent_low_fps": 0.0}
	cleaned.sort()
	var total: float = 0.0
	for ms in cleaned:
		total += ms
	var p99: float = _percentile(cleaned, 0.99)
	# Real 1%-low FPS is the mean duration of the slowest ceil(1%) frames.
	# 1000 / p99 is not the same metric when the capture has frame spikes.
	var tail_count: int = maxi(1, ceili(float(cleaned.size()) * 0.01))
	var tail_sum: float = 0.0
	for i in range(cleaned.size() - tail_count, cleaned.size()):
		tail_sum += cleaned[i]
	return {
		"count": cleaned.size(),
		"p50_ms": _percentile(cleaned, 0.50),
		"p95_ms": _percentile(cleaned, 0.95),
		"p99_ms": p99,
		"mean_ms": total / float(cleaned.size()),
		"one_percent_low_fps": 1000.0 * float(tail_count) / tail_sum,
	}


static func describe(result: Dictionary) -> String:
	if int(result.get("count", 0)) <= 0:
		return "CLIENT frame pacing: no valid samples"
	return "CLIENT frame pacing (CPU, not GPU): p50 %.2f ms | p95 %.2f ms | p99 %.2f ms | 1%% low %.1f fps | %d frames" % [
		float(result["p50_ms"]), float(result["p95_ms"]),
		float(result["p99_ms"]), float(result["one_percent_low_fps"]),
		int(result["count"])]


## GPU duration comes from native viewport timestamps. It does not include
## game CPU work, synchronization or display V-Sync time.
static func describe_gpu(result: Dictionary) -> String:
	if int(result.get("count", 0)) <= 0:
		return "GPU render time: unavailable (no valid timestamp samples)"
	return "GPU render time (viewport timestamp, not FPS): p50 %.2f ms | p95 %.2f ms | p99 %.2f ms | %d samples" % [
		float(result["p50_ms"]), float(result["p95_ms"]),
		float(result["p99_ms"]), int(result["count"])]
