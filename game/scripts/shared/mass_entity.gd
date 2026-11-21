extends RefCounted
## MassEntity-style data-oriented runtime: archetypes, structure-of-arrays fragments,
## processors with dependency ordering and optional parallel chunk execution.
##
## Design reference (concepts only, no code copied): Unreal Engine MassEntity
## https://dev.epicgames.com/documentation/en-us/unreal-engine/mass-entity-in-unreal-engine
## and the generic archetype ECS pattern (Unity DOTS / flecs, MIT) https://github.com/SanderMertens/flecs
## Implementation: original GDScript written for this project, MIT-compatible.

const INDEX_BITS := 24
const INDEX_MASK := (1 << INDEX_BITS) - 1

## fragment name -> Variant.Type (TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY)
var _fragment_types: Dictionary = {}
## archetype key -> index into _archetypes
var _archetype_lookup: Dictionary = {}
var _archetypes: Array[Dictionary] = []
var _generations: PackedInt32Array = PackedInt32Array()
var _slot_archetype: PackedInt32Array = PackedInt32Array()
var _slot_row: PackedInt32Array = PackedInt32Array()
var _free_slots: PackedInt32Array = PackedInt32Array()
var _alive_count: int = 0

var _processors: Array[Dictionary] = []
var _order: Array[int] = []
var _order_dirty: bool = true


func define_fragment(name: String, type: int) -> void:
	if type != TYPE_PACKED_VECTOR3_ARRAY and type != TYPE_PACKED_FLOAT32_ARRAY and type != TYPE_PACKED_INT32_ARRAY:
		push_error("MassEntity: unsupported fragment type for '%s'" % name)
		return
	_fragment_types[name] = type


func entity_count() -> int:
	return _alive_count


func archetype_count() -> int:
	return _archetypes.size()


func _make_array(type: int) -> Variant:
	match type:
		TYPE_PACKED_VECTOR3_ARRAY:
			return PackedVector3Array()
		TYPE_PACKED_FLOAT32_ARRAY:
			return PackedFloat32Array()
		_:
			return PackedInt32Array()


func _default_value(type: int) -> Variant:
	match type:
		TYPE_PACKED_VECTOR3_ARRAY:
			return Vector3.ZERO
		TYPE_PACKED_FLOAT32_ARRAY:
			return 0.0
		_:
			return 0


func _archetype_for(names: Array) -> int:
	var key := ",".join(PackedStringArray(names))
	if _archetype_lookup.has(key):
		return int(_archetype_lookup[key])
	var chunk: Dictionary = {}
	for fname in names:
		chunk[fname] = _make_array(int(_fragment_types[fname]))
	var ids := PackedInt32Array()
	chunk["_ids"] = ids
	chunk["_count"] = 0
	var arch: Dictionary = {"names": names, "chunk": chunk}
	_archetypes.append(arch)
	_archetype_lookup[key] = _archetypes.size() - 1
	return _archetypes.size() - 1


func _pack(index: int, gen: int) -> int:
	return (gen << INDEX_BITS) | index


func create(fragments: Dictionary) -> int:
	var names: Array = fragments.keys()
	for fname in names:
		if not _fragment_types.has(fname):
			push_error("MassEntity: undefined fragment '%s'" % str(fname))
			return -1
	names.sort()
	var ai := _archetype_for(names)
	var chunk: Dictionary = _archetypes[ai]["chunk"]
	var slot: int
	if _free_slots.size() > 0:
		slot = _free_slots[_free_slots.size() - 1]
		_free_slots.resize(_free_slots.size() - 1)
	else:
		slot = _generations.size()
		_generations.append(1)
		_slot_archetype.append(-1)
		_slot_row.append(0)
	var row: int = int(chunk["_count"])
	for fname in names:
		var arr: Variant = chunk[fname]
		var v: Variant = fragments[fname]
		arr.append(v)
		chunk[fname] = arr
	var ids: PackedInt32Array = chunk["_ids"]
	ids.append(slot)
	chunk["_ids"] = ids
	chunk["_count"] = row + 1
	_slot_archetype[slot] = ai
	_slot_row[slot] = row
	_alive_count += 1
	return _pack(slot, _generations[slot])


func is_alive(id: int) -> bool:
	if id < 0:
		return false
	var slot := id & INDEX_MASK
	if slot >= _generations.size():
		return false
	return _slot_archetype[slot] >= 0 and _generations[slot] == (id >> INDEX_BITS)


func destroy(id: int) -> void:
	if not is_alive(id):
		return
	var slot := id & INDEX_MASK
	var ai := _slot_archetype[slot]
	var row := _slot_row[slot]
	var arch: Dictionary = _archetypes[ai]
	var chunk: Dictionary = arch["chunk"]
	var last: int = int(chunk["_count"]) - 1
	var names: Array = arch["names"]
	var ids: PackedInt32Array = chunk["_ids"]
	var moved_slot := ids[last]
	for fname in names:
		var arr: Variant = chunk[fname]
		arr[row] = arr[last]
		arr.resize(last)
		chunk[fname] = arr
	ids[row] = moved_slot
	ids.resize(last)
	chunk["_ids"] = ids
	chunk["_count"] = last
	_slot_row[moved_slot] = row
	_slot_archetype[slot] = -1
	# Generation wraps well before overflowing the packed int range.
	_generations[slot] = (_generations[slot] + 1) & 0x3FFFFF
	if _generations[slot] == 0:
		_generations[slot] = 1
	_free_slots.append(slot)
	_alive_count -= 1


func has_fragment(id: int, fragment: String) -> bool:
	if not is_alive(id):
		return false
	var chunk: Dictionary = _archetypes[_slot_archetype[id & INDEX_MASK]]["chunk"]
	return chunk.has(fragment)


func get_value(id: int, fragment: String) -> Variant:
	if not has_fragment(id, fragment):
		return null
	var slot := id & INDEX_MASK
	var chunk: Dictionary = _archetypes[_slot_archetype[slot]]["chunk"]
	return chunk[fragment][_slot_row[slot]]


func set_value(id: int, fragment: String, v: Variant) -> void:
	if not has_fragment(id, fragment):
		return
	var slot := id & INDEX_MASK
	var chunk: Dictionary = _archetypes[_slot_archetype[slot]]["chunk"]
	chunk[fragment][_slot_row[slot]] = v


## Archetype chunks holding every required fragment. A chunk is a Dictionary of
## packed arrays by fragment name plus "_ids" (slot per row) and "_count".
## Write through chunk[name][i] = v to mutate in place.
func query(required: PackedStringArray) -> Array:
	var out: Array = []
	for arch in _archetypes:
		var names: Array = arch["names"]
		var ok := true
		for r in required:
			if not names.has(r):
				ok = false
				break
		if ok:
			var chunk: Dictionary = arch["chunk"]
			if int(chunk["_count"]) > 0:
				out.append(chunk)
	return out


func add_processor(name: String, required: PackedStringArray, callable: Callable, depends_on: PackedStringArray = PackedStringArray(), parallel: bool = false) -> void:
	_processors.append({
		"name": name, "required": required, "callable": callable,
		"deps": depends_on, "parallel": parallel,
	})
	_order_dirty = true


func remove_processor(name: String) -> void:
	for i in _processors.size():
		if _processors[i]["name"] == name:
			_processors.remove_at(i)
			_order_dirty = true
			return


## Processor names in execution order (Kahn topological sort, stable by registration).
func processor_order() -> PackedStringArray:
	_rebuild_order()
	var out := PackedStringArray()
	for i in _order:
		out.append(String(_processors[i]["name"]))
	return out


func _rebuild_order() -> void:
	if not _order_dirty:
		return
	_order_dirty = false
	_order.clear()
	var n := _processors.size()
	var by_name: Dictionary = {}
	for i in n:
		by_name[_processors[i]["name"]] = i
	var done := PackedByteArray()
	done.resize(n)
	var placed := 0
	while placed < n:
		var progressed := false
		for i in n:
			if done[i] == 1:
				continue
			var ready := true
			for d in (_processors[i]["deps"] as PackedStringArray):
				if by_name.has(d) and done[int(by_name[d])] == 0:
					ready = false
					break
			if ready:
				done[i] = 1
				_order.append(i)
				placed += 1
				progressed = true
		if not progressed:
			push_error("MassEntity: processor dependency cycle")
			for i in n:
				if done[i] == 0:
					_order.append(i)
			return


func run(delta: float) -> void:
	_rebuild_order()
	for i in _order:
		var p: Dictionary = _processors[i]
		var chunks: Array = query(p["required"])
		var callable: Callable = p["callable"]
		if bool(p["parallel"]) and chunks.size() > 1:
			var task := func(idx: int) -> void:
				var c: Dictionary = chunks[idx]
				callable.call(c, int(c["_count"]), delta)
			var gid := WorkerThreadPool.add_group_task(task, chunks.size(), -1, true)
			WorkerThreadPool.wait_for_group_task_completion(gid)
		else:
			for c in chunks:
				callable.call(c, int((c as Dictionary)["_count"]), delta)
