extends RefCounted
## Snapshot baseline delta compression.
## Inspired by Quake 3 (delta against the last acknowledged snapshot), Overwatch
## netcode talks (only changed fields on the wire) and Unreal Iris (per-property dirty tracking).
## State is Dictionary id(int) -> Dictionary field -> Variant. A delta holds
##   "changed": {id: {field: value}}  only fields that differ from the baseline
##   "added":   {id: full entity}     entities absent from the baseline
##   "removed": PackedInt64Array      entity ids gone since the baseline
##   "dropped": {id: Array}           (only when needed) fields deleted from a kept entity


## `tolerances` maps field name -> float epsilon; float values (and Vector2/3) within it are not resent.
static func diff(baseline: Dictionary, current: Dictionary, tolerances: Dictionary = {}) -> Dictionary:
	var changed: Dictionary = {}
	var added: Dictionary = {}
	var removed := PackedInt64Array()
	var dropped: Dictionary = {}
	for id in current:
		var cur_ent: Dictionary = current[id]
		if not baseline.has(id):
			added[id] = _copy(cur_ent)
			continue
		var base_ent: Dictionary = baseline[id]
		var fields: Dictionary = {}
		for field in cur_ent:
			var value: Variant = cur_ent[field]
			if base_ent.has(field):
				var tol: float = float(tolerances.get(field, 0.0))
				if _same(base_ent[field], value, tol):
					continue
			fields[field] = _copy(value)
		if not fields.is_empty():
			changed[id] = fields
		var gone: Array = []
		for field in base_ent:
			if not cur_ent.has(field):
				gone.append(field)
		if not gone.is_empty():
			dropped[id] = gone
	for id in baseline:
		if not current.has(id):
			removed.append(int(id))
	var out: Dictionary = {"changed": changed, "added": added, "removed": removed}
	if not dropped.is_empty():
		out["dropped"] = dropped
	return out


## Returns a new state; the baseline is never mutated or aliased.
static func apply(baseline: Dictionary, delta: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var removed: PackedInt64Array = delta.get("removed", PackedInt64Array())
	var retired: Dictionary = {}
	for id in removed:
		retired[id] = true
	# Entities leaving the interest set never need a deep copy. Keep the
	# original insertion order of survivors, then process additions as before.
	for id in baseline:
		if not retired.has(id):
			out[id] = _copy(baseline[id])
	var added: Dictionary = delta.get("added", {})
	for id in added:
		out[id] = _copy(added[id])
	var changed: Dictionary = delta.get("changed", {})
	for id in changed:
		if not out.has(id):
			continue
		var ent: Dictionary = out[id]
		var fields: Dictionary = changed[id]
		for field in fields:
			ent[field] = _copy(fields[field])
	var dropped: Dictionary = delta.get("dropped", {})
	for id in dropped:
		if not out.has(id):
			continue
		var ent2: Dictionary = out[id]
		var gone: Array = dropped[id]
		for field in gone:
			ent2.erase(field)
	return out


static func _copy(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	if v is Array:
		var a: Array = v
		return a.duplicate(true)
	return v


static func _same(a: Variant, b: Variant, tol: float) -> bool:
	if typeof(a) != typeof(b):
		return false
	if tol > 0.0:
		if a is float:
			return absf(float(a) - float(b)) <= tol
		if a is Vector3:
			var va: Vector3 = a
			var vb: Vector3 = b
			return va.distance_to(vb) <= tol
		if a is Vector2:
			var wa: Vector2 = a
			var wb: Vector2 = b
			return wa.distance_to(wb) <= tol
	return a == b
