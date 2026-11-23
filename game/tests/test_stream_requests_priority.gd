extends RefCounted
## Streaming queue must preserve stable priority order across small and large budgets.

const StreamRequests = preload("res://scripts/shared/stream_requests.gd")


func run(t) -> void:
	t.current = "top-K streaming batches match the full priority sort"
	for budget in [1, 2, 4, 5, 8, 16, 17]:
		var queue := StreamRequests.new()
		var expected: Array[Dictionary] = []
		for i in 32:
			var priority: float = float((i * 13) % 11) * 0.5
			var cell := Vector2i(i, -i)
			queue.request(cell, priority, 7)
			expected.append({"cell": cell, "priority": priority, "seq": i})
		expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_priority: float = float(a["priority"])
			var b_priority: float = float(b["priority"])
			if a_priority != b_priority:
				return a_priority > b_priority
			return int(a["seq"]) < int(b["seq"])
		)
		var batch: Array[Vector2i] = queue.next_batch(budget)
		t.eq(batch.size(), budget, "batch serves its requested budget")
		for index in batch.size():
			t.eq(batch[index], expected[index]["cell"],
				"small and large budgets use the same stable priority ordering")

	t.current = "large priority queues match full sorting for all interactive budgets"
	for budget in [1, 6, 12, 16, 17]:
		var dense := StreamRequests.new()
		var reference: Array[Dictionary] = []
		for i in 512:
			var priority: float = float((i * 47) % 39) * 0.25
			var cell := Vector2i(i - 256, i % 23)
			dense.request(cell, priority, 14)
			reference.append({"cell": cell, "priority": priority, "seq": i})
		reference.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a["priority"]) != float(b["priority"]):
				return float(a["priority"]) > float(b["priority"])
			return int(a["seq"]) < int(b["seq"]))
		var batch: Array[Vector2i] = dense.next_batch(budget)
		t.eq(batch.size(), budget, "requested large-scene streaming budget is respected")
		for i in batch.size():
			t.eq(batch[i], reference[i]["cell"],
				"stable priority of 512 requests agrees with the full sort")

	t.current = "non-finite priorities are rejected without changing the generation"
	var invalid := StreamRequests.new()
	t.check(not invalid.request(Vector2i(0, 0), NAN, 1),
		"NaN priority is rejected")
	t.check(not invalid.request(Vector2i(1, 0), INF, 1),
		"infinite priority is rejected")
	t.check(not invalid.request(Vector2i(4, 0), NAN, 99),
		"invalid future generation cannot supersede legitimate loads")
	t.check(invalid.request(Vector2i(2, 0), 2.0, 1),
		"finite priority from current generation is accepted")
	t.eq(int(invalid.stats()["rejected_invalid"]), 3,
		"rejected priorities are counted in diagnostics")
	t.eq(invalid.next_batch(3), [Vector2i(2, 0)],
		"invalid requests never enter the load queue")

	t.current = "in-flight cap still bounds small priority batches"
	var capped := StreamRequests.new()
	capped.max_in_flight = 2
	for i in 5:
		capped.request(Vector2i(i, 0), float(i), 4)
	t.eq(capped.next_batch(4).size(), 2, "queue does not exceed its in-flight cap")
	t.eq(capped.next_batch(4).size(), 0, "queue respects the occupied in-flight slots")
	t.check(capped.complete(Vector2i(4, 0), "ready"), "highest priority chunk completes")
	var next: Array[Vector2i] = capped.next_batch(4)
	t.eq(next.size(), 1, "released slot allows exactly one new load")
	t.eq(next[0], Vector2i(2, 0), "next queued priority is preserved")
