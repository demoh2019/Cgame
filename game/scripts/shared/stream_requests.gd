extends RefCounted
## Prioritised streaming request queue with generations. Every request is stamped with the
## "generation" (e.g. a counter bumped each time the player's cell/interest set changes). When the
## interest set moves, `cancel_stale` drops queued requests that are no longer wanted and flags the
## in-flight ones, so results that arrive late are ignored by `complete`.
##
## Concept (not code) from UE World Partition / level streaming request cancellation and generic
## job-system generation tokens. Original GDScript; no third-party code copied, so no license
## obligations.

enum State { QUEUED, IN_FLIGHT, CANCELLED }


class Req extends RefCounted:
	var cell: Vector2i
	var priority: float = 0.0
	var generation: int = 0
	var state: int = State.QUEUED
	var seq: int = 0


## Cap on simultaneously in-flight requests (0 = unlimited).
var max_in_flight: int = 0
var newest_generation: int = 0

var _reqs: Dictionary = {}
var _seq: int = 0
var _completed: Array[Dictionary] = []
var _stats: Dictionary = {
	"requested": 0, "completed": 0, "cancelled_queued": 0, "cancelled_inflight": 0,
	"dropped_late": 0, "rejected_stale": 0, "rejected_invalid": 0, "revived": 0,
}


## Queue (or re-prioritise) a cell. Higher priority is served first. Returns false when the
## request's generation is older than one already seen (stale, ignored).
func request(cell: Vector2i, priority: float, generation: int) -> bool:
	# Nonfinite priorities break strict, deterministic chunk ordering.
	if not is_finite(priority):
		_stats["rejected_invalid"] = int(_stats["rejected_invalid"]) + 1
		return false
	if generation < newest_generation:
		_stats["rejected_stale"] = int(_stats["rejected_stale"]) + 1
		return false
	newest_generation = generation
	if _reqs.has(cell):
		var r: Req = _reqs[cell]
		r.generation = maxi(r.generation, generation)
		if r.state == State.CANCELLED:
			r.state = State.IN_FLIGHT
			_stats["revived"] = int(_stats["revived"]) + 1
		elif r.state == State.QUEUED:
			r.priority = maxf(r.priority, priority)
		return true
	var n := Req.new()
	n.cell = cell
	n.priority = priority
	n.generation = generation
	n.seq = _seq
	_seq += 1
	_reqs[cell] = n
	_stats["requested"] = int(_stats["requested"]) + 1
	return true


## Cancels everything older than `current_generation` except cells in `keep_cells` (which are
## re-stamped with the current generation). Returns the number of cancelled requests.
func cancel_stale(current_generation: int, keep_cells: Array) -> int:
	newest_generation = maxi(newest_generation, current_generation)
	var keep: Dictionary = {}
	for c in keep_cells:
		keep[c] = true
	var cancelled := 0
	for cell in _reqs.keys():
		var r: Req = _reqs[cell]
		if keep.has(cell):
			r.generation = maxi(r.generation, current_generation)
			if r.state == State.CANCELLED:
				r.state = State.IN_FLIGHT
				_stats["revived"] = int(_stats["revived"]) + 1
			continue
		if r.generation >= current_generation or r.state == State.CANCELLED:
			continue
		cancelled += 1
		if r.state == State.QUEUED:
			_reqs.erase(cell)
			_stats["cancelled_queued"] = int(_stats["cancelled_queued"]) + 1
		else:
			r.state = State.CANCELLED
			_stats["cancelled_inflight"] = int(_stats["cancelled_inflight"]) + 1
	return cancelled


static func _before(a: Req, b: Req) -> bool:
	if a.priority != b.priority:
		return a.priority > b.priority
	return a.seq < b.seq


## Pops up to `budget` highest-priority queued requests and marks them in flight.
func next_batch(budget: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var allowed := budget
	if max_in_flight > 0:
		allowed = mini(allowed, max_in_flight - in_flight_count())
	if allowed <= 0:
		return out
	var queued: Array[Req] = []
	# Most frame budgets request only a handful of chunks. Keep a bounded,
	# sorted top-K instead of sorting every queued cell on each frame.
	for r: Req in _reqs.values():
		if r.state != State.QUEUED:
			continue
		if allowed <= 4:
			var pos: int = 0
			while pos < queued.size() and not _before(r, queued[pos]):
				pos += 1
			if pos < allowed:
				queued.insert(pos, r)
				if queued.size() > allowed:
					queued.pop_back()
		else:
			queued.append(r)
	if allowed > 4:
		queued.sort_custom(_before)
	for i in mini(allowed, queued.size()):
		queued[i].state = State.IN_FLIGHT
		out.append(queued[i].cell)
	return out


## Delivers a finished load. Returns false (and discards the result) when the request was
## cancelled, superseded by a newer generation, or never existed.
func complete(cell: Vector2i, result: Variant) -> bool:
	if not _reqs.has(cell):
		_stats["dropped_late"] = int(_stats["dropped_late"]) + 1
		return false
	var r: Req = _reqs[cell]
	if r.state == State.CANCELLED or r.state == State.QUEUED or r.generation < newest_generation:
		if r.state != State.QUEUED:
			_reqs.erase(cell)
		_stats["dropped_late"] = int(_stats["dropped_late"]) + 1
		return false
	_reqs.erase(cell)
	_stats["completed"] = int(_stats["completed"]) + 1
	_completed.append({"cell": cell, "result": result, "generation": r.generation})
	return true


func take_completed() -> Array[Dictionary]:
	var out := _completed
	_completed = []
	return out


func has_request(cell: Vector2i) -> bool:
	return _reqs.has(cell)


func state_of(cell: Vector2i) -> int:
	if not _reqs.has(cell):
		return -1
	var r: Req = _reqs[cell]
	return r.state


func queued_count() -> int:
	return _count(State.QUEUED)


func in_flight_count() -> int:
	return _count(State.IN_FLIGHT) + _count(State.CANCELLED)


func _count(state: int) -> int:
	var n := 0
	for r: Req in _reqs.values():
		if r.state == state:
			n += 1
	return n


func stats() -> Dictionary:
	var s := _stats.duplicate()
	s["queued"] = queued_count()
	s["in_flight"] = in_flight_count()
	return s
