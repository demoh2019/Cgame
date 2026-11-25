extends RefCounted
## Queue budget remains deterministic even with dense streaming requests.
const StreamRequests = preload("res://scripts/shared/stream_requests.gd")
const LagFallback = preload("res://scripts/server/lag_compensation.gd")


func run(t) -> void:
	t.current = "streaming work respects priority, stable ties and in-flight cap"
	var stream := StreamRequests.new()
	stream.max_in_flight = 2
	t.check(stream.request(Vector2i(1, 0), 2.0, 1), "queue first cell")
	t.check(stream.request(Vector2i(2, 0), 2.0, 1), "queue same priority cell")
	t.check(stream.request(Vector2i(3, 0), 0.5, 1), "queue lower priority cell")
	t.eq(stream.next_batch(1), [Vector2i(1, 0)],
		"equal priority uses initial request sequence")
	t.eq(stream.next_batch(20), [Vector2i(2, 0)],
		"maximum concurrent workers is respected")
	t.eq(stream.next_batch(10), [], "a full worker pool cannot issue extra work")
	t.check(stream.complete(Vector2i(1, 0), {"value": 11}),
		"completed highest priority work is accepted")
	t.eq(stream.next_batch(10), [Vector2i(3, 0)],
		"next queued cell starts when a worker becomes free")
	t.eq(stream.cancel_stale(2, [Vector2i(3, 0)]), 1,
		"new interest cancels obsolete in-flight cells")
	t.check(not stream.complete(Vector2i(2, 0), {"value": -1}),
		"obsolete asynchronous results never enter the game")
	t.check(stream.complete(Vector2i(3, 0), {"value": 33}),
		"retained in-flight cells complete at the newer generation")
	t.eq(stream.queued_count(), 0, "no stray queued work")
	t.eq(stream.in_flight_count(), 0, "cancelled work releases the worker slot")
	t.check(not stream.request(Vector2i(4, 0), 7.0, 1),
		"stale generations cannot reintroduce unloaded cells")

	t.current = "bounded top budget matches global priority ordering"
	var large := StreamRequests.new()
	var ranked: Array[Dictionary] = []
	for i in 120:
		var priority: float = float((i * 17) % 19)
		var cell := Vector2i(i, -i)
		large.request(cell, priority, 5)
		ranked.append({"cell": cell, "priority": priority, "seq": i})
	# Refreshing an existing cell raises its priority without changing arrival order.
	large.request(Vector2i(3, -3), 100.0, 5)
	ranked[3]["priority"] = 100.0
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["priority"]) != float(b["priority"]):
			return float(a["priority"]) > float(b["priority"])
		return int(a["seq"]) < int(b["seq"]))
	var expected: Array[Vector2i] = []
	for i in 5:
		expected.append(ranked[i]["cell"])
	t.eq(large.next_batch(5), expected,
		"five scheduled cells match a full deterministic priority sort")
	t.eq(large.in_flight_count(), 5, "only selected top-five cells become in-flight")
	t.eq(large.queued_count(), 115, "all other cells remain queued")
 
	t.current = "invalid stream priorities leave generations and queues intact"
	var guard := StreamRequests.new()
	t.check(not guard.request(Vector2i(1, 0), NAN, 99),
		"NaN priority is rejected")
	t.check(not guard.request(Vector2i(1, 0), INF, 99),
		"infinite priority is rejected")
	t.eq(guard.newest_generation, 0,
		"invalid requests cannot advance the generation and lock out future work")
	t.eq(int(guard.stats()["rejected_invalid"]), 2,
		"invalid scheduling attempts are counted")
	t.check(guard.request(Vector2i(2, 0), 1.0, 1),
		"valid finite priority still enters the queue")
	t.eq(guard.next_batch(1), [Vector2i(2, 0)],
		"valid world streaming still schedules after rejected inputs")

	t.current = "native streaming queue rejects invalid priorities when supported"
	if ClassDB.class_exists("StreamRequestQueue"):
		var native_queue: Object = ClassDB.instantiate("StreamRequestQueue")
		if native_queue.stats().has("rejected_invalid"):
			t.check(not native_queue.request(Vector2i(1, 0), NAN, 99),
				"native queue rejects nonfinite priorities before advancing generation")
			t.eq(native_queue.get_newest_generation(), 0, "native generation stays valid")
			t.check(native_queue.request(Vector2i(2, 0), 1.0, 1), "valid load still queues")
			t.eq(native_queue.next_batch(1), [Vector2i(2, 0)], "native queue returns valid load")

	t.current = "server lag history is bounded and monotonic"
	var history := LagFallback.new()
	history.record(7, 1.0, Vector3(1, 0, 0))
	history.record(7, 1.0, Vector3(2, 0, 0))
	history.record(7, 0.9, Vector3(90, 0, 0))
	history.record(7, NAN, Vector3(99, 0, 0))
	history.record(7, 1.05, Vector3.INF)
	t.eq(history.sample_count(7), 1, "duplicate and invalid samples do not grow history")
	history.record(7, 1.1, Vector3(4, 0, 0))
	t.near(history.position_at(7, 1.05, Vector3.ZERO).x, 3.0, 0.0001,
		"latest same-tick pose participates in interpolation")
	t.eq(history.position_at(7, NAN, Vector3.ONE), Vector3.ONE,
		"invalid rewind time returns live position")
	for i in 256:
		history.record(8, 2.0 + float(i) * 0.0001, Vector3(i, 0, 0))
	t.eq(history.sample_count(8), 128, "high-frequency history has a hard memory cap")
