extends RefCounted
## Streaming queue must preserve stable priority order across small and large budgets.

const StreamRequests = preload("res://scripts/shared/stream_requests.gd")


func run(t) -> void:
	t.current = "top-K streaming batches match the full priority sort"
	for budget in [1, 2, 4, 5, 8, 16, 32, 40, 64, 96, 128]:
		var queue := StreamRequests.new()
		var expected: Array[Dictionary] = []
		for i in 128:
			var priority: float = float((i * 13) % 11) * 0.5
			var cell := Vector2i(i, -i)
			queue.request(cell, priority, 7)
			expected.append({"cell": cell, "priority": priority, "seq": i})
		# Reprioritising an old cell must not lose its initial tie-order.
		queue.request(Vector2i(7, -7), 100.0, 7)
		expected[7]["priority"] = 100.0
		expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_priority: float = float(a["priority"])
			var b_priority: float = float(b["priority"])
			if a_priority != b_priority:
				return a_priority > b_priority
			return int(a["seq"]) < int(b["seq"])
		)
		var batch: Array[Vector2i] = queue.next_batch(budget)
		t.eq(batch.size(), budget, "batch serves its requested budget")
		t.eq(batch[0], Vector2i(7, -7), "reprioritised cell wins the first slot")
		for index in batch.size():
			t.eq(batch[index], expected[index]["cell"],
				"small and large budgets use the same stable priority ordering")

	t.current = "medium-sized world streaming budgets retain stable ranking"
	var many := StreamRequests.new()
	var reference: Array[Dictionary] = []
	for i in 330:
		var priority: float = float((i * 29) % 41)
		var cell := Vector2i(-i, i)
		many.request(cell, priority, 9)
		reference.append({"cell": cell, "priority": priority, "seq": i})
	reference.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["priority"]) != float(b["priority"]):
			return float(a["priority"]) > float(b["priority"])
		return int(a["seq"]) < int(b["seq"]))
	var actual: Array[Vector2i] = many.next_batch(128)
	t.eq(actual.size(), 128, "medium-size streaming batch uses bounded heap")
	for j in actual.size():
		t.eq(actual[j], reference[j]["cell"],
			"large bounded top-K matches full priority order")
	# Remaining cells still sort consistently beyond the heap threshold.
	var remaining: Array[Vector2i] = many.next_batch(201)
	for j in remaining.size():
		t.eq(remaining[j], reference[128 + j]["cell"],
			"bulk world loading preserves global priority after heap batch")

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
