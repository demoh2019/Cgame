extends SceneTree
## Command-line integration/regression suite for prediction_buffer.gd.
## Exit code is nonzero whenever an assertion fails.

const PredictionBuffer = preload("res://prediction_buffer.gd")
const ImpairmentQueue = preload("res://impairment_queue.gd")

var _assertions: int = 0
var _failures: int = 0
var _cases: int = 0
var _reject_replay_tick: int = -1


func _initialize() -> void:
	_test_uninitialized_access()
	_test_initial_state_is_copied()
	_test_sequential_prediction()
	_test_out_of_order_command()
	_test_invalid_input()
	_test_invalid_simulation_result()
	_test_command_snapshot_is_immutable()
	_test_nested_state_snapshot_is_immutable()
	_test_exact_authoritative_match()
	_test_authoritative_replay()
	_test_authoritative_latest_tick()
	_test_replay_is_idempotent()
	_test_replay_from_baseline()
	_test_future_authoritative_tick()
	_test_buffer_eviction()
	_test_stale_authoritative_tick()
	_test_configure_history_validation()
	_test_smaller_history_trims_old_entries()
	_test_reinitialize_clears_old_history()
	_test_reset()
	_test_custom_comparator()
	_test_invalid_comparator()
	_test_atomic_replay_failure()
	_test_mutating_simulator_does_not_leak()
	_test_reject_object_state()
	_test_reject_nonfinite_values()
	_test_reject_deep_or_oversize_containers()
	_test_preserve_vector_state()
	_test_queue_zero_delay()
	_test_queue_delayed_delivery()
	_test_queue_fifo_tie_break()
	_test_queue_drop_all()
	_test_queue_no_loss()
	_test_queue_jitter_determinism()
	_test_queue_seed_changes_pattern()
	_test_queue_reordering()
	_test_queue_time_validation()
	_test_queue_payload_validation()
	_test_queue_payload_is_copied()
	_test_queue_due_time_bounds()
	_test_queue_reset()
	_test_queue_invalid_configuration()
	_test_queue_full_limit()
	print("PredictionBuffer: %d cases, %d assertions, %d failures." %
			[_cases, _assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)


func _begin_case() -> void:
	_cases += 1


func _new_buffer(limit: int = 128):
	var result = PredictionBuffer.new()
	_check(result.configure_history(limit), "configure valid history")
	_check(result.initialize(0, {"x": 0.0, "tick": 0}, Callable(self, "_advance")),
			"initialize with a pure simulator")
	return result


func _advance(state: Dictionary, command: Dictionary, tick: int) -> Dictionary:
	var output := state.duplicate(true)
	output["x"] = float(output.get("x", 0.0)) + float(command.get("dx", 0.0))
	output["tick"] = tick
	return output


func _invalid_step(_state: Dictionary, _input: Dictionary, _tick: int) -> Dictionary:
	return {"x": INF}


func _conditional_step(state: Dictionary, command: Dictionary, tick: int) -> Dictionary:
	if tick == _reject_replay_tick:
		return {"x": INF}
	return _advance(state, command, tick)


func _mutating_step(state: Dictionary, command: Dictionary, tick: int) -> Dictionary:
	state["nested"]["value"] = 99
	command["dx"] = 123
	return {"x": state["nested"]["value"], "tick": tick}


func _approx_equal(a: Dictionary, b: Dictionary) -> bool:
	return a["tick"] == b["tick"] and absf(float(a["x"]) - float(b["x"])) < 0.1


func _bad_equal(_a: Dictionary, _b: Dictionary) -> String:
	return "invalid"


func _test_uninitialized_access() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	_check(not b.is_initialized(), "fresh predictor is uninitialized")
	_check(b.get_current_tick() == -1, "initial tick sentinel")
	_check(b.get_current_state().is_empty(), "no state before initialization")
	_check(b.predict(1, {"dx": 1})["status"] == "uninitialized", "predict guarded")
	_check(b.reconcile(0, {})["status"] == "uninitialized", "reconcile guarded")


func _test_initial_state_is_copied() -> void:
	_begin_case()
	var state := {"x": 0.0, "tick": 0, "extra": {"value": 7}}
	var b = PredictionBuffer.new()
	_check(b.initialize(0, state, Callable(self, "_advance")), "initialize copies state")
	state["extra"]["value"] = 100
	_check(b.get_current_state()["extra"]["value"] == 7, "caller does not own stored state")


func _test_sequential_prediction() -> void:
	_begin_case()
	var b = _new_buffer()
	_check(b.predict(1, {"dx": 2})["ok"], "first tick succeeds")
	_check(b.predict(2, {"dx": -3})["ok"], "second tick succeeds")
	_check(b.get_current_tick() == 2, "latest tick moves forward")
	_check(b.get_current_state()["x"] == -1.0, "deterministic sum")
	_check(b.get_state_at(1)["x"] == 2.0, "historical state retained")


func _test_out_of_order_command() -> void:
	_begin_case()
	var b = _new_buffer()
	_check(b.predict(2, {"dx": 1})["status"] == "out_of_order", "gap is rejected")
	_check(b.predict(0, {"dx": 1})["status"] == "out_of_order", "duplicate baseline rejected")
	_check(b.get_current_tick() == 0, "rejected command doesn't move tick")


func _test_invalid_input() -> void:
	_begin_case()
	var b = _new_buffer()
	_check(b.predict(1, {"value": RefCounted.new()})["status"] == "invalid_command",
			"Object input forbidden")
	_check(b.predict(1, {"dx": NAN})["status"] == "invalid_command", "NaN command forbidden")
	_check(b.get_current_tick() == 0, "rejection is atomic")


func _test_invalid_simulation_result() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	_check(b.initialize(0, {"x": 0}, Callable(self, "_invalid_step")), "initialize bad simulator")
	_check(b.predict(1, {"dx": 1})["status"] == "invalid_simulation_result",
			"nonfinite simulator result rejected")
	_check(b.get_current_tick() == 0, "invalid simulation never advances")


func _test_command_snapshot_is_immutable() -> void:
	_begin_case()
	var b = _new_buffer()
	var command := {"dx": 2.0, "nested": {"flag": true}}
	_check(b.predict(1, command)["ok"], "input accepted")
	command["nested"]["flag"] = false
	command["dx"] = 99.0
	var stored: Dictionary = b.get_buffered_command(1)
	_check(stored["dx"] == 2.0, "source mutation cannot affect stored command")
	_check(stored["nested"]["flag"] == true, "source nested mutation isolated")
	stored["nested"]["flag"] = false
	_check(b.get_buffered_command(1)["nested"]["flag"] == true,
			"returned nested command cannot affect stored command")


func _test_nested_state_snapshot_is_immutable() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	_check(b.initialize(0, {"x": 0, "nested": {"v": 3}}, Callable(self, "_advance")),
			"nested state accepted")
	var snapshot: Dictionary = b.get_current_state()
	snapshot["nested"]["v"] = 9
	_check(b.get_current_state()["nested"]["v"] == 3, "state getter deep clones")


func _test_exact_authoritative_match() -> void:
	_begin_case()
	var b = _new_buffer()
	b.predict(1, {"dx": 2})
	_check(b.reconcile(1, {"x": 2.0, "tick": 1})["status"] == "matched",
			"no replay for identical authoritative state")
	_check(b.get_current_state()["x"] == 2.0, "match preserves state")


func _test_authoritative_replay() -> void:
	_begin_case()
	var b = _new_buffer()
	for i in range(1, 5):
		b.predict(i, {"dx": 1})
	var result: Dictionary = b.reconcile(2, {"x": 9.0, "tick": 2})
	_check(result["ok"], "authoritative correction accepted")
	_check(result["status"] == "replayed", "correction triggers replay")
	_check(result["replayed_steps"] == 2, "only later ticks replay")
	_check(b.get_state_at(2)["x"] == 9.0, "corrected baseline stored")
	_check(b.get_current_state()["x"] == 11.0, "later commands re-applied")
	_check(b.get_current_tick() == 4, "replay doesn't change timeline")


func _test_authoritative_latest_tick() -> void:
	_begin_case()
	var b = _new_buffer()
	b.predict(1, {"dx": 4})
	var result: Dictionary = b.reconcile(1, {"x": 7.0, "tick": 1})
	_check(result["replayed_steps"] == 0, "no future steps to replay")
	_check(b.get_current_state()["x"] == 7.0, "authoritative latest snapshot installed")


func _test_replay_is_idempotent() -> void:
	_begin_case()
	var b = _new_buffer()
	b.predict(1, {"dx": 1})
	b.predict(2, {"dx": 1})
	b.reconcile(1, {"x": 4.0, "tick": 1})
	_check(b.reconcile(1, {"x": 4.0, "tick": 1})["status"] == "matched",
			"repeating the same correction does not replay")
	_check(b.get_current_state()["x"] == 5.0, "idempotent reconciliation")


func _test_replay_from_baseline() -> void:
	_begin_case()
	var b = _new_buffer()
	b.predict(1, {"dx": 5})
	b.predict(2, {"dx": 1})
	var result: Dictionary = b.reconcile(0, {"x": 10.0, "tick": 0})
	_check(result["replayed_steps"] == 2, "replay from initial tick")
	_check(b.get_current_state()["x"] == 16.0, "initial state corrected")


func _test_future_authoritative_tick() -> void:
	_begin_case()
	var b = _new_buffer()
	_check(b.reconcile(3, {"x": 0, "tick": 3})["status"] == "future_tick",
			"future ticks rejected")
	_check(b.get_current_tick() == 0, "future correction does not mutate history")


func _test_buffer_eviction() -> void:
	_begin_case()
	var b = _new_buffer(2)
	for tick in range(1, 5):
		b.predict(tick, {"dx": 1})
	_check(b.get_earliest_tick() == 2, "old baseline evicted")
	_check(b.get_state_at(1).is_empty(), "old state no longer retained")
	_check(b.get_buffered_command(2).is_empty(), "command for evicted baseline pruned")
	_check(b.get_buffered_command(3)["dx"] == 1, "replay command retained")
	_check(b.get_current_state()["x"] == 4, "latest state persists")


func _test_stale_authoritative_tick() -> void:
	_begin_case()
	var b = _new_buffer(2)
	for tick in range(1, 5):
		b.predict(tick, {"dx": 1})
	_check(b.reconcile(1, {"x": 100, "tick": 1})["status"] == "stale_tick",
			"stale correction cannot rewrite expired history")
	_check(b.get_current_state()["x"] == 4, "stale correction is non-destructive")


func _test_configure_history_validation() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	_check(not b.configure_history(1), "history must have at least 2 steps")
	_check(not b.configure_history(2049), "history has hard max")
	_check(b.configure_history(2048), "2048-step history supported")
	_check(b.get_history_limit() == 2048, "limit is retained")


func _test_smaller_history_trims_old_entries() -> void:
	_begin_case()
	var b = _new_buffer()
	for tick in range(1, 6):
		b.predict(tick, {"dx": 1})
	_check(b.configure_history(2), "history shrink accepted")
	_check(b.get_earliest_tick() == 3, "history trimmed on reconfiguration")
	_check(b.get_current_tick() == 5, "latest tick preserved")


func _test_reinitialize_clears_old_history() -> void:
	_begin_case()
	var b = _new_buffer()
	b.predict(1, {"dx": 3})
	_check(b.initialize(100, {"x": 50.0, "tick": 100}, Callable(self, "_advance")),
			"re-initialize at different tick")
	_check(b.get_state_at(1).is_empty(), "past history cleared")
	_check(b.get_current_tick() == 100, "timeline replaced")
	_check(b.predict(101, {"dx": 2})["ok"], "next tick resumes")


func _test_reset() -> void:
	_begin_case()
	var b = _new_buffer()
	b.predict(1, {"dx": 7})
	b.reset()
	_check(not b.is_initialized(), "reset clears active state")
	_check(b.get_current_state().is_empty(), "reset clears snapshots")
	_check(b.get_current_tick() == -1, "reset clears tick")
	_check(b.predict(2, {})["status"] == "uninitialized", "must reinitialize after reset")


func _test_custom_comparator() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	_check(b.initialize(0, {"x": 0.0, "tick": 0}, Callable(self, "_advance"),
			Callable(self, "_approx_equal")), "custom comparator installed")
	b.predict(1, {"dx": 1})
	var result: Dictionary = b.reconcile(1, {"x": 1.01, "tick": 1})
	_check(result["status"] == "matched", "small drift tolerated")
	_check(b.get_current_state()["x"] == 1.0, "comparator match keeps predicted state")


func _test_invalid_comparator() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	b.initialize(0, {"x": 0.0, "tick": 0}, Callable(self, "_advance"),
			Callable(self, "_bad_equal"))
	b.predict(1, {"dx": 1})
	_check(b.reconcile(1, {"x": 10.0, "tick": 1})["status"] == "invalid_comparator_result",
			"invalid comparator result rejected")
	_check(b.get_current_state()["x"] == 1.0, "bad comparator is non-destructive")


func _test_atomic_replay_failure() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	_check(b.initialize(0, {"x": 0.0, "tick": 0}, Callable(self, "_conditional_step")),
			"conditional simulator installed")
	for tick in range(1, 4):
		b.predict(tick, {"dx": 1})
	var before: Dictionary = b.get_current_state()
	_reject_replay_tick = 3
	var result: Dictionary = b.reconcile(1, {"x": 100.0, "tick": 1})
	_reject_replay_tick = -1
	_check(result["status"] == "invalid_simulation_result", "failed replay rejected")
	_check(b.get_current_state() == before, "failed replay is transactional")
	_check(b.get_state_at(1)["x"] == 1.0, "initial correction not partially installed")


func _test_mutating_simulator_does_not_leak() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	b.initialize(0, {"nested": {"value": 1}}, Callable(self, "_mutating_step"))
	var command := {"dx": 3}
	_check(b.predict(1, command)["ok"], "mutating simulator accepted as snapshot")
	_check(b.get_state_at(0)["nested"]["value"] == 1, "prior state unchanged")
	_check(b.get_buffered_command(1)["dx"] == 3, "mutated input is not cached")
	_check(command["dx"] == 3, "caller-owned input remains unchanged")


func _test_reject_object_state() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	_check(not b.initialize(0, {"bad": RefCounted.new()}, Callable(self, "_advance")),
			"Object in initial state rejected")
	_check(not b.is_initialized(), "failed initialize is not active")


func _test_reject_nonfinite_values() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	_check(not b.initialize(0, {"x": INF}, Callable(self, "_advance")), "INF state rejected")
	_check(not b.initialize(0, {"v": Vector2(NAN, 0)}, Callable(self, "_advance")),
			"NaN vector rejected")
	_check(not b.initialize(0, {"color": Color(0, INF, 0)}, Callable(self, "_advance")),
			"nonfinite color rejected")


func _test_reject_deep_or_oversize_containers() -> void:
	_begin_case()
	var too_deep: Dictionary = {"v": 1}
	for _i in range(10):
		too_deep = {"next": too_deep}
	var large: Array = []
	large.resize(4097)
	var b = PredictionBuffer.new()
	_check(not b.initialize(0, too_deep, Callable(self, "_advance")), "depth limit enforced")
	_check(not b.initialize(0, {"big": large}, Callable(self, "_advance")),
			"collection size limit enforced")


func _test_preserve_vector_state() -> void:
	_begin_case()
	var b = PredictionBuffer.new()
	var state := {"position": Vector2(1, 2), "velocity": Vector2(-1, 1)}
	_check(b.initialize(0, state, Callable(self, "_advance")), "vector state accepted")
	_check(b.get_current_state()["position"] == Vector2(1, 2), "vector snapshot exact")


func _test_queue_zero_delay() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	var scheduled: Dictionary = queue.schedule({"id": 1}, 10)
	_check(scheduled["status"] == "scheduled", "zero-delay packet accepted")
	_check(scheduled["due_ms"] == 10, "default delay is zero")
	var ready: Array[Dictionary] = queue.poll_due(10)
	_check(ready.size() == 1, "packet is due immediately")
	_check(ready[0]["payload"]["id"] == 1, "payload survives")
	_check(queue.get_delivered_count() == 1, "delivery counter increments")


func _test_queue_delayed_delivery() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	_check(queue.configure(120, 0, 0.0, 4), "valid latency configuration")
	queue.schedule({"id": 3}, 100)
	_check(queue.poll_due(219).is_empty(), "packet not released early")
	_check(queue.get_pending_count() == 1, "pending packet retained")
	_check(queue.poll_due(220).size() == 1, "packet released at deadline")
	_check(queue.poll_due(400).is_empty(), "packet delivered exactly once")


func _test_queue_fifo_tie_break() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	queue.configure(100, 0, 0)
	for i in range(8):
		queue.schedule({"order": i}, 0)
	var ready: Array[Dictionary] = queue.poll_due(100)
	_check(ready.size() == 8, "all equal-deadline packets delivered")
	for i in range(8):
		_check(ready[i]["sequence"] == i, "equal deadlines sorted by sequence")
		_check(ready[i]["payload"]["order"] == i, "equal deadlines preserve payload")


func _test_queue_drop_all() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	queue.configure(50, 10, 1.0, 123)
	for i in range(5):
		_check(queue.schedule({"id": i}, 0)["status"] == "dropped", "100% loss drops packet")
	_check(queue.get_dropped_count() == 5, "drop counter tracks all lost packets")
	_check(queue.get_pending_count() == 0, "dropped packets not enqueued")
	_check(queue.poll_due(1000).is_empty(), "dropped packets never arrive")


func _test_queue_no_loss() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	queue.configure(10, 10, 0.0, 123)
	for i in range(30):
		_check(queue.schedule({"id": i}, 0)["status"] == "scheduled", "zero-loss packet kept")
	_check(queue.poll_due(1000).size() == 30, "all no-loss packets delivered")
	_check(queue.get_dropped_count() == 0, "no false drops")


func _test_queue_jitter_determinism() -> void:
	_begin_case()
	var a = ImpairmentQueue.new()
	var b = ImpairmentQueue.new()
	a.configure(100, 80, 0.3, 434)
	b.configure(100, 80, 0.3, 434)
	for i in range(50):
		var one: Dictionary = a.schedule({"i": i}, 0)
		var two: Dictionary = b.schedule({"i": i}, 0)
		_check(one == two, "same seed yields same drop/jitter decision")
	_check(a.poll_due(1000) == b.poll_due(1000), "same-seed delivery order repeats")


func _test_queue_seed_changes_pattern() -> void:
	_begin_case()
	var a = ImpairmentQueue.new()
	var b = ImpairmentQueue.new()
	a.configure(80, 60, 0.0, 1)
	b.configure(80, 60, 0.0, 2)
	var different := false
	for i in range(20):
		if a.schedule({"n": i}, 0)["due_ms"] != b.schedule({"n": i}, 0)["due_ms"]:
			different = true
	_check(different, "different seeds vary jitter timing")


func _test_queue_reordering() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	queue.configure(100, 100, 0, 12345)
	for i in range(40):
		queue.schedule({"id": i}, 0)
	var ready: Array[Dictionary] = queue.poll_due(300)
	_check(ready.size() == 40, "all jitter packets delivered")
	var inverted := false
	for i in range(1, ready.size()):
		_check(ready[i]["due_ms"] >= ready[i - 1]["due_ms"], "poll sorted by due time")
		if ready[i]["sequence"] < ready[i - 1]["sequence"]:
			inverted = true
	_check(inverted, "jitter can reorder delivery")


func _test_queue_time_validation() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	_check(queue.schedule({"x": 1}, -1)["status"] == "invalid_time", "negative send time rejected")
	_check(queue.schedule({"x": 1}, 9223372036854775807)["status"] == "invalid_time", "overflowing deadline rejected")
	_check(queue.poll_due(-1).is_empty(), "negative poll time safe")
	_check(queue.get_pending_count() == 0, "invalid time not enqueued")
	_check(queue.get_dropped_count() == 0, "invalid send not counted as loss")


func _test_queue_payload_validation() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	_check(queue.schedule({"obj": RefCounted.new()}, 1)["status"] == "invalid_payload",
			"Object payload rejected")
	_check(queue.schedule({"float": NAN}, 1)["status"] == "invalid_payload",
			"nonfinite payload rejected")
	_check(queue.get_pending_count() == 0, "invalid payload not queued")


func _test_queue_payload_is_copied() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	queue.configure(10, 0, 0)
	var payload := {"nested": {"id": 10}}
	queue.schedule(payload, 0)
	payload["nested"]["id"] = 999
	var ready: Array[Dictionary] = queue.poll_due(10)
	_check(ready.size() == 1, "snapshot delivered")
	_check(ready[0]["payload"]["nested"]["id"] == 10,
			"transport snapshot immune to caller mutation")


func _test_queue_due_time_bounds() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	queue.configure(5, 20, 0, 9)
	for i in range(100):
		var result: Dictionary = queue.schedule({"i": i}, 100)
		_check(result["due_ms"] >= 100, "deadline never before enqueue")
		_check(result["due_ms"] <= 125, "deadline limited by latency and jitter")


func _test_queue_reset() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	queue.configure(1, 0, 0)
	queue.schedule({"id": 1}, 0)
	queue.poll_due(1)
	queue.schedule({"id": 2}, 1)
	queue.reset()
	_check(queue.get_pending_count() == 0, "reset clears pending queue")
	_check(queue.get_delivered_count() == 0, "reset clears delivered counter")
	_check(queue.get_dropped_count() == 0, "reset clears dropped counter")
	_check(queue.schedule({"id": 3}, 0)["sequence"] == 0, "reset restarts sequence")


func _test_queue_invalid_configuration() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	queue.configure(10, 0, 0)
	queue.schedule({"id": 1}, 0)
	_check(not queue.configure(-1, 0, 0), "negative latency invalid")
	_check(not queue.configure(1, -1, 0), "negative jitter invalid")
	_check(not queue.configure(1, 0, -0.1), "negative loss invalid")
	_check(not queue.configure(1, 0, 1.01), "loss above 100% invalid")
	_check(not queue.configure(1, 0, INF), "nonfinite loss invalid")
	_check(queue.get_pending_count() == 1, "invalid config leaves previous queue intact")
	_check(queue.poll_due(10).size() == 1, "valid config remains active")


func _test_queue_full_limit() -> void:
	_begin_case()
	var queue = ImpairmentQueue.new()
	queue.configure(1000, 0, 0)
	for i in range(8192):
		queue.schedule({"id": i}, 0)
	_check(queue.get_pending_count() == 8192, "bounded queue reaches capacity")
	_check(queue.schedule({"id": 8192}, 0)["status"] == "queue_full",
			"overflow rejected without mutating pending packets")
	_check(queue.poll_due(1000).size() == 8192, "all accepted packets retained")
