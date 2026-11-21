@tool
extends RefCounted
## Smart Object registry: slots, exclusive claims with timeouts, query scoring,
## placement scoring / automatic placement and per-behavior interaction graphs.
## Original implementation inspired by the public concept of Unreal Engine's
## Smart Objects; no third-party source code was copied.
##
## Object: {id, position: Vector3, tags: Array, slots: [{offset: Vector3, behavior: String, tags: Array}]}
## Positions are world Vector3; 2D areas (Rect2) map x -> world x, y -> world z.
## Behavior graph: array of steps {anim: String, duration: float, effect: String}.

var on_effect: Callable = Callable() ## (effect: String, user: Variant, object_id: String) -> void
var release_on_complete: bool = true
var default_claim_timeout: float = 10.0

var _objects: Dictionary = {}
var _behaviors: Dictionary = {}
var _claims: Dictionary = {}
var _slot_claim: Dictionary = {}
var _next_handle: int = 1


func register_behavior(behavior: String, steps: Array) -> void:
	_behaviors[behavior] = steps.duplicate(true)


func register_object(obj: Dictionary) -> bool:
	if not obj.has("id") or not obj.has("position"):
		return false
	var copy: Dictionary = obj.duplicate(true)
	if not copy.has("tags"):
		copy["tags"] = []
	if not copy.has("slots"):
		copy["slots"] = []
	_objects[str(copy["id"])] = copy
	return true


func unregister_object(id: String) -> void:
	if not _objects.has(id):
		return
	var obj: Dictionary = _objects[id]
	var slots: Array = obj["slots"]
	for i in slots.size():
		var key := _key(id, i)
		if _slot_claim.has(key):
			release(int(_slot_claim[key]))
	_objects.erase(id)


func has_object(id: String) -> bool:
	return _objects.has(id)


func object_count() -> int:
	return _objects.size()


func slot_position(obj: Dictionary, slot_index: int) -> Vector3:
	var slots: Array = obj["slots"]
	var slot: Dictionary = slots[slot_index]
	var base: Vector3 = obj["position"]
	var off: Vector3 = slot.get("offset", Vector3.ZERO)
	return base + off


func is_slot_free(id: String, slot_index: int) -> bool:
	return not _slot_claim.has(_key(id, slot_index))


## query: {position: Vector3, radius: float, required_tags: Array, preferred_tags: Array,
## behavior: String, include_claimed: bool}. Returns [{object, slot, position, distance, score}],
## best score first (ties: object id, slot index).
func find(query: Dictionary) -> Array:
	var pos: Vector3 = query.get("position", Vector3.ZERO)
	var radius: float = float(query.get("radius", 50.0))
	var required: Array = query.get("required_tags", [])
	var preferred: Array = query.get("preferred_tags", [])
	var behavior: String = str(query.get("behavior", ""))
	var include_claimed: bool = bool(query.get("include_claimed", false))
	var results: Array = []
	for key in _objects:
		var obj: Dictionary = _objects[key]
		var obj_tags: Array = obj["tags"]
		var slots: Array = obj["slots"]
		for i in slots.size():
			var slot: Dictionary = slots[i]
			if behavior != "" and str(slot.get("behavior", "")) != behavior:
				continue
			if not include_claimed and not is_slot_free(str(obj["id"]), i):
				continue
			var slot_tags: Array = slot.get("tags", [])
			if not _has_all(required, obj_tags, slot_tags):
				continue
			var p := slot_position(obj, i)
			var d := pos.distance_to(p)
			if d > radius:
				continue
			var closeness := 1.0 - d / maxf(radius, 0.0001)
			var bonus := 0.0
			if not preferred.is_empty():
				var hit := 0
				for tag in preferred:
					if obj_tags.has(tag) or slot_tags.has(tag):
						hit += 1
				bonus = float(hit) / float(preferred.size())
			results.append({"object": str(obj["id"]), "slot": i, "position": p,
					"distance": d, "score": closeness + bonus})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a["score"], b["score"]):
			return a["score"] > b["score"]
		if a["object"] != b["object"]:
			return a["object"] < b["object"]
		return a["slot"] < b["slot"])
	return results


## Claims a slot exclusively. Returns a handle > 0, or 0 when unavailable.
## timeout < 0 uses default_claim_timeout; timeout == 0 never expires.
func claim(object_id: String, slot_index: int, user: Variant, timeout: float = -1.0) -> int:
	if not _objects.has(object_id):
		return 0
	var obj: Dictionary = _objects[object_id]
	var slots: Array = obj["slots"]
	if slot_index < 0 or slot_index >= slots.size():
		return 0
	var key := _key(object_id, slot_index)
	if _slot_claim.has(key):
		return 0
	var handle := _next_handle
	_next_handle += 1
	var t: float = default_claim_timeout if timeout < 0.0 else timeout
	_claims[handle] = {"object": object_id, "slot": slot_index, "user": user, "timeout": t,
			"left": t, "step": -1, "t": 0.0, "interacting": false}
	_slot_claim[key] = handle
	return handle


func release(handle: int) -> bool:
	if not _claims.has(handle):
		return false
	var c: Dictionary = _claims[handle]
	_slot_claim.erase(_key(str(c["object"]), int(c["slot"])))
	_claims.erase(handle)
	return true


func is_claimed(handle: int) -> bool:
	return _claims.has(handle)


func claim_user(handle: int) -> Variant:
	if not _claims.has(handle):
		return null
	var c: Dictionary = _claims[handle]
	return c["user"]


## Resets the idle timeout of a claim (user is still on its way).
func touch(handle: int) -> void:
	if _claims.has(handle):
		var c: Dictionary = _claims[handle]
		c["left"] = c["timeout"]


func start_interaction(handle: int) -> bool:
	if not _claims.has(handle):
		return false
	var c: Dictionary = _claims[handle]
	var steps := _steps_of(c)
	if steps.is_empty():
		return false
	c["interacting"] = true
	c["step"] = -1
	c["t"] = 0.0
	_begin_step(handle, c, 0)
	return true


## Returns {step, anim, t, duration, done} or {} when not interacting.
func interaction_state(handle: int) -> Dictionary:
	if not _claims.has(handle):
		return {}
	var c: Dictionary = _claims[handle]
	if not bool(c["interacting"]):
		return {}
	var steps := _steps_of(c)
	var s: Dictionary = steps[int(c["step"])]
	return {"step": c["step"], "anim": s.get("anim", ""), "t": c["t"],
			"duration": float(s.get("duration", 0.0))}


## Advances interactions and claim timeouts. Returns handles of interactions finished this call.
func advance(dt: float) -> Array:
	var finished: Array = []
	var expired: Array = []
	for handle in _claims.keys():
		var c: Dictionary = _claims[handle]
		if bool(c["interacting"]):
			var left := dt
			while left > 0.0 and bool(c["interacting"]):
				var steps := _steps_of(c)
				var step_i: int = c["step"]
				var s: Dictionary = steps[step_i]
				var dur: float = maxf(float(s.get("duration", 0.0)), 0.0)
				var remaining: float = dur - float(c["t"])
				if left < remaining:
					c["t"] = float(c["t"]) + left
					left = 0.0
				else:
					left -= remaining
					if step_i + 1 < steps.size():
						_begin_step(int(handle), c, step_i + 1)
					else:
						c["interacting"] = false
						finished.append(handle)
		else:
			if float(c["timeout"]) > 0.0:
				c["left"] = float(c["left"]) - dt
				if float(c["left"]) <= 0.0:
					expired.append(handle)
	for handle in expired:
		release(int(handle))
	if release_on_complete:
		for handle in finished:
			release(int(handle))
	return finished


## Score in [0, 1] for putting a new object at candidate_pos. 0 when unreachable or closer than
## min_spacing to an existing object / `placed` position. `density` is how many neighbours
## within 2.5x min_spacing are tolerated before the score falls off.
func placement_score(candidate_pos: Vector3, nav_reachable: Callable, density: float,
		placed: Array = [], min_spacing: float = 0.0) -> float:
	if nav_reachable.is_valid() and not bool(nav_reachable.call(candidate_pos)):
		return 0.0
	var near := 0
	var ring := maxf(min_spacing, 0.001) * 2.5
	for p_v in _all_positions(placed):
		var d := candidate_pos.distance_to(p_v)
		if d < min_spacing:
			return 0.0
		if d < ring:
			near += 1
	var tolerated := maxf(density, 1.0)
	return clampf(1.0 - float(near) / (tolerated * 2.0), 0.05, 1.0)


## Deterministic automatic placement. rules: {min_spacing, density, nav_reachable: Callable,
## candidates: int (samples per object)}. Returns up to `count` positions (Vector3, y = 0).
func auto_place(area: Rect2, count: int, rules: Dictionary, rng_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var spacing: float = float(rules.get("min_spacing", 1.0))
	var density: float = float(rules.get("density", 2.0))
	var nav: Callable = rules.get("nav_reachable", Callable())
	var samples: int = int(rules.get("candidates", 16))
	var placed: Array = []
	for _n in count:
		var best := Vector3.ZERO
		var best_score := 0.0
		for _s in samples:
			var cand := Vector3(rng.randf_range(area.position.x, area.end.x), 0.0,
					rng.randf_range(area.position.y, area.end.y))
			var sc := placement_score(cand, nav, density, placed, spacing)
			if sc > best_score:
				best_score = sc
				best = cand
		if best_score > 0.0:
			placed.append(best)
	return placed


# --- internals -------------------------------------------------------------

func _key(id: String, slot_index: int) -> String:
	return "%s#%d" % [id, slot_index]


func _has_all(required: Array, a: Array, b: Array) -> bool:
	for tag in required:
		if not a.has(tag) and not b.has(tag):
			return false
	return true


func _steps_of(c: Dictionary) -> Array:
	var obj: Dictionary = _objects.get(str(c["object"]), {})
	if obj.is_empty():
		return []
	var slots: Array = obj["slots"]
	var slot: Dictionary = slots[int(c["slot"])]
	var steps: Array = _behaviors.get(str(slot.get("behavior", "")), [])
	return steps


func _begin_step(_handle: int, c: Dictionary, index: int) -> void:
	c["step"] = index
	c["t"] = 0.0
	var steps := _steps_of(c)
	var s: Dictionary = steps[index]
	var effect: String = str(s.get("effect", ""))
	if effect != "" and on_effect.is_valid():
		on_effect.call(effect, c["user"], str(c["object"]))


func _all_positions(extra: Array) -> Array:
	var out: Array = extra.duplicate()
	for key in _objects:
		var obj: Dictionary = _objects[key]
		out.append(obj["position"])
	return out
