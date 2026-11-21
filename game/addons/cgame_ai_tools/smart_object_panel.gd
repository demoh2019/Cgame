@tool
extends VBoxContainer
## Smart Object placement editor: place / move / delete objects and slots, preview and commit
## automatic placement (SmartObjects.auto_place), and export the layout as JSON. Edits are kept
## in plain data and mirrored into a SmartObjects registry so find()/claims can be tried live.

const SmartObjects = preload("res://scripts/shared/smart_objects.gd")

signal changed
signal selection_changed(obj_id: String)

var registry: SmartObjects = SmartObjects.new()
var selected_id: String = ""

var _objects: Dictionary = {}
var _auto_counter: int = 0
var _list: ItemList = null
var _canvas: Control = null


func _init() -> void:
	_build_ui()


func object_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _objects:
		out.append(String(k))
	out.sort()
	return out


func get_object(obj_id: String) -> Dictionary:
	return (_objects.get(obj_id, {}) as Dictionary).duplicate(true)


func place_object(obj_id: String, pos: Vector3, tags: Array = []) -> bool:
	if obj_id == "" or _objects.has(obj_id):
		return false
	_objects[obj_id] = {"id": obj_id, "position": pos, "tags": tags.duplicate(), "slots": []}
	_sync(obj_id)
	return true


func move_object(obj_id: String, pos: Vector3) -> bool:
	if not _objects.has(obj_id):
		return false
	(_objects[obj_id] as Dictionary)["position"] = pos
	_sync(obj_id)
	return true


func delete_object(obj_id: String) -> bool:
	if not _objects.has(obj_id):
		return false
	_objects.erase(obj_id)
	registry.unregister_object(obj_id)
	if selected_id == obj_id:
		select("")
	_after_change()
	return true


func add_slot(obj_id: String, offset: Vector3, behavior: String = "", tags: Array = []) -> int:
	if not _objects.has(obj_id):
		return -1
	var slots: Array = (_objects[obj_id] as Dictionary)["slots"]
	slots.append({"offset": offset, "behavior": behavior, "tags": tags.duplicate()})
	_sync(obj_id)
	return slots.size() - 1


func move_slot(obj_id: String, slot_index: int, offset: Vector3) -> bool:
	if not _objects.has(obj_id):
		return false
	var slots: Array = (_objects[obj_id] as Dictionary)["slots"]
	if slot_index < 0 or slot_index >= slots.size():
		return false
	(slots[slot_index] as Dictionary)["offset"] = offset
	_sync(obj_id)
	return true


func delete_slot(obj_id: String, slot_index: int) -> bool:
	if not _objects.has(obj_id):
		return false
	var slots: Array = (_objects[obj_id] as Dictionary)["slots"]
	if slot_index < 0 or slot_index >= slots.size():
		return false
	slots.remove_at(slot_index)
	_sync(obj_id)
	return true


func select(obj_id: String) -> void:
	selected_id = obj_id if _objects.has(obj_id) else ""
	selection_changed.emit(selected_id)
	if _canvas != null:
		_canvas.queue_redraw()


## Auto placement preview: positions only, nothing is committed.
func preview_auto_place(area: Rect2, cnt: int, rules: Dictionary, rng_seed: int) -> Array:
	return registry.auto_place(area, cnt, rules, rng_seed)


## Commit auto placement: creates objects from `template` ({tags, slots}). Returns created ids.
func commit_auto_place(area: Rect2, cnt: int, rules: Dictionary, rng_seed: int, template: Dictionary = {}) -> Array[String]:
	var created: Array[String] = []
	for p_v in preview_auto_place(area, cnt, rules, rng_seed):
		var p: Vector3 = p_v
		var obj_id: String = "auto_%d" % _auto_counter
		_auto_counter += 1
		if place_object(obj_id, p, template.get("tags", [])):
			for s_v in template.get("slots", []):
				var s: Dictionary = s_v
				add_slot(obj_id, s.get("offset", Vector3.ZERO), String(s.get("behavior", "")), s.get("tags", []))
			created.append(obj_id)
	return created


func export_data() -> Dictionary:
	var objs: Array = []
	for obj_id in object_ids():
		var o: Dictionary = _objects[obj_id]
		var slots_out: Array = []
		for s_v in (o["slots"] as Array):
			var s: Dictionary = s_v
			slots_out.append({"offset": _v3(s.get("offset", Vector3.ZERO)), "behavior": String(s.get("behavior", "")),
					"tags": (s.get("tags", []) as Array).duplicate()})
		objs.append({"id": obj_id, "position": _v3(o["position"]), "tags": (o["tags"] as Array).duplicate(), "slots": slots_out})
	return {"version": 1, "objects": objs}


func export_json(indent: String = "\t") -> String:
	return JSON.stringify(export_data(), indent)


func import_json(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	var data: Dictionary = parsed
	if not (data.get("objects") is Array):
		return false
	for id_old in object_ids():
		registry.unregister_object(id_old)
	_objects.clear()
	for o_v in (data["objects"] as Array):
		var o: Dictionary = o_v
		var obj_id: String = String(o.get("id", ""))
		if not place_object(obj_id, _from_v3(o.get("position", [0, 0, 0])), o.get("tags", [])):
			continue
		for s_v in (o.get("slots", []) as Array):
			var s: Dictionary = s_v
			add_slot(obj_id, _from_v3(s.get("offset", [0, 0, 0])), String(s.get("behavior", "")), s.get("tags", []))
	_after_change()
	return true


func save_json(path: String) -> Error:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(export_json())
	return OK


# --- internals -------------------------------------------------------------

static func _v3(v: Variant) -> Array:
	var p: Vector3 = v
	return [p.x, p.y, p.z]


static func _from_v3(a: Variant) -> Vector3:
	var arr: Array = a
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _sync(obj_id: String) -> void:
	registry.register_object((_objects[obj_id] as Dictionary).duplicate(true))
	_after_change()


func _after_change() -> void:
	if _list != null:
		_list.clear()
		for obj_id in object_ids():
			_list.add_item("%s (%d slots)" % [obj_id, ((_objects[obj_id] as Dictionary)["slots"] as Array).size()])
	if _canvas != null:
		_canvas.queue_redraw()
	changed.emit()


func _build_ui() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	var add_b := Button.new()
	add_b.text = "Place at origin"
	add_b.pressed.connect(func() -> void: place_object("obj_%d" % _objects.size(), Vector3.ZERO))
	bar.add_child(add_b)
	var del_b := Button.new()
	del_b.text = "Delete"
	del_b.pressed.connect(func() -> void: delete_object(selected_id))
	bar.add_child(del_b)
	var slot_b := Button.new()
	slot_b.text = "+Slot"
	slot_b.pressed.connect(func() -> void: add_slot(selected_id, Vector3(1, 0, 0)))
	bar.add_child(slot_b)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(240, 100)
	_list.item_selected.connect(func(i: int) -> void:
		var ids: Array[String] = object_ids()
		if i >= 0 and i < ids.size():
			select(ids[i]))
	add_child(_list)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(240, 140)
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)


func _draw_map() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.1, 0.11, 0.13))
	for obj_id in object_ids():
		var o: Dictionary = _objects[obj_id]
		var p: Vector3 = o["position"]
		var c: Vector2 = _canvas.size * 0.5 + Vector2(p.x, p.z) * 4.0
		_canvas.draw_circle(c, 5.0, Color(1, 0.8, 0.2) if obj_id == selected_id else Color(0.4, 0.7, 1.0))
		for s_v in (o["slots"] as Array):
			var s: Dictionary = s_v
			var off: Vector3 = s.get("offset", Vector3.ZERO)
			_canvas.draw_circle(c + Vector2(off.x, off.z) * 4.0, 2.5, Color(0.6, 1.0, 0.6))
