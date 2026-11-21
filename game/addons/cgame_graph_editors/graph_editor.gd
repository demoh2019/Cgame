@tool
extends Control
## Generic node-graph editor (Godot GraphEdit) for Cgame graph assets: visual scripts, PCG,
## VFX, audio and StateTree. Works in the editor (bottom panel) and at runtime / in tests.
##
## Original code on top of Godot's GraphEdit/GraphNode API (Godot Engine, MIT licence).
## Edits go through a snapshot command stack (undo()/redo()). Assets are plain Dictionaries
## in each runtime's own format; adapters.gd maps them to/from the editor's neutral model.
##
## When this control is not inside a SceneTree the view is rebuilt synchronously; inside a tree
## UI-driven edits rebuild on idle (call flush_view() to force it).

const Adapters = preload("res://addons/cgame_graph_editors/adapters.gd")

signal changed
signal validated(errors: Array[String])

const MAX_UNDO := 200

## Optional Callable(runtime: RefCounted) invoked on the runtime used by validate(), so the host
## can register functions / tasks / conditions of its own.
var runtime_setup: Callable = Callable()
## When false (default) unknown whitelisted names (call fn, tasks, conditions) are stubbed in validate().
var strict_names: bool = false

var kind: String = ""

var _model: Dictionary = {"nodes": {}, "conns": [], "meta": {}}
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _graph: GraphEdit
var _toolbar: HBoxContainer
var _kind_opt: OptionButton
var _add_menu: MenuButton
var _undo_btn: Button
var _redo_btn: Button
var _log: Label
var _dialog: FileDialog
var _dialog_save: bool = false
var _gn_by_id: Dictionary = {}
var _id_by_name: Dictionary = {}
var _status: Dictionary = {}
var _serial: int = 0
var _view_dirty: bool = false
var _building: bool = false


func _init() -> void:
	_build_ui()


# ---------------------------------------------------------------- public API

## Loads an asset of the given kind. Returns false when the kind is unknown.
func load_asset(asset_kind: String, asset: Dictionary) -> bool:
	if not Adapters.is_kind(asset_kind):
		return false
	kind = asset_kind
	_model = Adapters.load_model(kind, asset)
	_undo_stack.clear()
	_redo_stack.clear()
	_status.clear()
	_populate_palette()
	_select_kind_option()
	_rebuild_view()
	_update_buttons()
	return true


func new_asset(asset_kind: String) -> bool:
	return load_asset(asset_kind, Adapters.empty_asset(asset_kind))


func to_asset() -> Dictionary:
	return Adapters.store_model(kind, _model)


## Editor-level problems first (e.g. detached nodes), then the runtime's own validation.
func validate() -> Array[String]:
	var errs: Array[String] = []
	if kind == "":
		errs.append("no graph loaded")
		return errs
	errs.append_array(Adapters.validate_model(kind, _model))
	errs.append_array(Adapters.validate_asset(kind, to_asset(), runtime_setup, strict_names))
	_show_log(errs)
	validated.emit(errs)
	return errs


func node_count() -> int:
	var nodes: Dictionary = _model["nodes"]
	return nodes.size()


func connection_count() -> int:
	var conns: Array = _model["conns"]
	return conns.size()


func node_ids() -> Array[String]:
	var out: Array[String] = []
	var nodes: Dictionary = _model["nodes"]
	for id in nodes:
		out.append(str(id))
	return out


func has_graph_node(id: String) -> bool:
	var nodes: Dictionary = _model["nodes"]
	return nodes.has(id)


func node_type(id: String) -> String:
	var nodes: Dictionary = _model["nodes"]
	if not nodes.has(id):
		return ""
	var n: Dictionary = nodes[id]
	return str(n["type"])


func node_params(id: String) -> Dictionary:
	var nodes: Dictionary = _model["nodes"]
	if not nodes.has(id):
		return {}
	var n: Dictionary = nodes[id]
	var p: Dictionary = n["params"]
	return p.duplicate(true)


func node_position(id: String) -> Vector2:
	var nodes: Dictionary = _model["nodes"]
	if not nodes.has(id):
		return Vector2.ZERO
	var n: Dictionary = nodes[id]
	var p: Vector2 = n["pos"]
	return p


## Slot ports of the GraphNode for `id` as {"in": [pin dicts], "out": [pin dicts]}.
func node_pins(id: String) -> Dictionary:
	return _pins_for(id)


func palette() -> Array[String]:
	return Adapters.palette(kind)


func get_graph_edit() -> GraphEdit:
	return _graph


## Adds a node of a palette type. Returns the new id ("" when the type is unknown).
func add_node(type: String, pos: Vector2 = Vector2.ZERO, params: Dictionary = {}, id: String = "") -> String:
	if kind == "" or not Adapters.palette(kind).has(type):
		return ""
	var nodes: Dictionary = _model["nodes"]
	var nid: String = id if id != "" else Adapters.new_id(type, nodes)
	if nodes.has(nid):
		return ""
	var before: Dictionary = _snapshot()
	var p: Dictionary = Adapters.default_params(kind, type)
	p.merge(params.duplicate(true), true)
	nodes[nid] = {"type": type, "params": p, "pos": pos, "has_pos": true}
	Adapters.on_node_added(kind, _model, nid)
	_commit("add " + type, before)
	return nid


func remove_nodes(ids: Array) -> void:
	var nodes: Dictionary = _model["nodes"]
	var doomed: Dictionary = {}
	for id in ids:
		if nodes.has(str(id)):
			doomed[str(id)] = true
	if doomed.is_empty():
		return
	var before: Dictionary = _snapshot()
	for id in doomed:
		nodes.erase(id)
		Adapters.on_node_removed(kind, _model, str(id))
		_status.erase(id)
	var kept: Array = []
	var conns: Array = _model["conns"]
	for c_v in conns:
		var c: Dictionary = c_v
		if not doomed.has(c["from"]) and not doomed.has(c["to"]):
			kept.append(c)
	_model["conns"] = kept
	_commit("delete", before)


## Returns "" on success, otherwise why the link was refused. Single-input pins (and single-output
## pins) replace an existing link.
func connect_nodes(from_id: String, from_pin: String, to_id: String, to_pin: String) -> String:
	var err: String = _connect_error(from_id, from_pin, to_id, to_pin)
	if err != "":
		return err
	var before: Dictionary = _snapshot()
	var pins_from: Dictionary = _pins_for(from_id)
	var pins_to: Dictionary = _pins_for(to_id)
	var fp: Dictionary = _find_pin(pins_from["out"], from_pin)
	var tp: Dictionary = _find_pin(pins_to["in"], to_pin)
	var kept: Array = []
	var conns: Array = _model["conns"]
	for c_v in conns:
		var c: Dictionary = c_v
		var drop: bool = false
		if not bool(tp["multi"]) and c["to"] == to_id and c["to_pin"] == to_pin:
			drop = true
		if not bool(fp["multi"]) and c["from"] == from_id and c["from_pin"] == from_pin:
			drop = true
		if not drop:
			kept.append(c)
	kept.append({"from": from_id, "from_pin": from_pin, "to": to_id, "to_pin": to_pin})
	_model["conns"] = kept
	_commit("connect", before)
	return ""


func disconnect_nodes(from_id: String, from_pin: String, to_id: String, to_pin: String) -> bool:
	var conns: Array = _model["conns"]
	var idx: int = -1
	for i in conns.size():
		var c: Dictionary = conns[i]
		if c["from"] == from_id and c["from_pin"] == from_pin and c["to"] == to_id and c["to_pin"] == to_pin:
			idx = i
			break
	if idx < 0:
		return false
	var before: Dictionary = _snapshot()
	conns.remove_at(idx)
	_commit("disconnect", before)
	return true


func move_node(id: String, pos: Vector2) -> void:
	var nodes: Dictionary = _model["nodes"]
	if not nodes.has(id):
		return
	var before: Dictionary = _snapshot()
	var n: Dictionary = nodes[id]
	n["pos"] = pos
	n["has_pos"] = true
	_commit("move", before, false)
	var gn: GraphNode = _gn_by_id.get(id) as GraphNode
	if gn != null:
		gn.position_offset = pos


func set_param(id: String, key: String, value: Variant) -> bool:
	var nodes: Dictionary = _model["nodes"]
	if not nodes.has(id):
		return false
	var n: Dictionary = nodes[id]
	var p: Dictionary = n["params"]
	if p.has(key) and hash(p[key]) == hash(value) and typeof(p[key]) == typeof(value):
		return false
	var before: Dictionary = _snapshot()
	p[key] = value
	_commit("set " + key, before)
	return true


## Marks a node as the asset entry: audio output node or state tree root.
func set_entry(id: String) -> bool:
	var field: String = Adapters.entry_field(kind)
	if field == "" or not has_graph_node(id):
		return false
	var before: Dictionary = _snapshot()
	var meta: Dictionary = _model["meta"]
	meta[field] = id
	_commit("set " + field, before)
	return true


func get_entry() -> String:
	var field: String = Adapters.entry_field(kind)
	var meta: Dictionary = _model["meta"]
	return str(meta.get(field, "")) if field != "" else ""


## Free-form top level asset field (visual script "variables"/"machines", PCG "seed", ...).
func set_meta_field(key: String, value: Variant) -> void:
	var before: Dictionary = _snapshot()
	var meta: Dictionary = _model["meta"]
	meta[key] = value
	_commit("set " + key, before)


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var cmd: Dictionary = _undo_stack.pop_back()
	_redo_stack.append(cmd)
	_model = (cmd["before"] as Dictionary).duplicate(true)
	_after_history_step()
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	var cmd: Dictionary = _redo_stack.pop_back()
	_undo_stack.append(cmd)
	_model = (cmd["after"] as Dictionary).duplicate(true)
	_after_history_step()
	return true


func save_json(path: String) -> Error:
	var doc: Dictionary = {"cgame_graph": 1, "kind": kind, "asset": Adapters.encode_value(to_asset())}
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	return OK


func load_json(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	var doc: Dictionary = parsed
	if not doc.has("kind") or not doc.has("asset"):
		return false
	var asset: Variant = Adapters.decode_value(doc["asset"])
	if not (asset is Dictionary):
		return false
	return load_asset(str(doc["kind"]), asset)


## Debug overlay: shows `text` (runtime value, trace hit count, ...) under a node. Empty text hides it.
func set_node_status(node_id: String, text: String) -> void:
	if text == "":
		_status.erase(node_id)
	else:
		_status[node_id] = text
	var gn: GraphNode = _gn_by_id.get(node_id) as GraphNode
	if gn != null:
		_apply_status(gn, node_id)


func get_node_status(node_id: String) -> String:
	return str(_status.get(node_id, ""))


func clear_node_status() -> void:
	_status.clear()
	for id in _gn_by_id:
		_apply_status(_gn_by_id[id] as GraphNode, str(id))


## Number of GraphNodes / GraphEdit connections currently shown (after any pending rebuild).
func view_node_count() -> int:
	flush_view()
	var n: int = 0
	for ch in _graph.get_children():
		if ch is GraphNode:
			n += 1
	return n


func view_connection_count() -> int:
	flush_view()
	return _graph.get_connection_list().size()


func flush_view() -> void:
	if _view_dirty:
		_rebuild_view()


# ---------------------------------------------------------------- history

func _snapshot() -> Dictionary:
	return _model.duplicate(true)


func _commit(label: String, before: Dictionary, rebuild: bool = true) -> void:
	if hash(before) == hash(_model):
		return
	_undo_stack.append({"label": label, "before": before, "after": _model.duplicate(true)})
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()
	_redo_stack.clear()
	if rebuild:
		_request_rebuild()
	_update_buttons()
	changed.emit()


func _after_history_step() -> void:
	_request_rebuild()
	_update_buttons()
	changed.emit()


func _request_rebuild() -> void:
	if is_inside_tree():
		if not _view_dirty:
			_view_dirty = true
			call_deferred("flush_view")
	else:
		_rebuild_view()


# ---------------------------------------------------------------- pins / connection rules

func _pins_for(id: String) -> Dictionary:
	var nodes: Dictionary = _model["nodes"]
	if not nodes.has(id):
		return {"in": [], "out": []}
	var n: Dictionary = nodes[id]
	var res: Dictionary = Adapters.pins(kind, str(n["type"]), n["params"])
	var ins: Array = (res["in"] as Array).duplicate()
	var outs: Array = (res["out"] as Array).duplicate()
	# Links that reference pins the adapter does not know (hand edited assets) still get a port.
	var conns: Array = _model["conns"]
	for c_v in conns:
		var c: Dictionary = c_v
		if c["to"] == id and _find_pin(ins, str(c["to_pin"])).is_empty():
			ins.append({"name": str(c["to_pin"]), "slot": 1, "multi": true, "label": str(c["to_pin"]), "ptype": ""})
		if c["from"] == id and _find_pin(outs, str(c["from_pin"])).is_empty():
			outs.append({"name": str(c["from_pin"]), "slot": 1, "multi": true, "label": str(c["from_pin"]), "ptype": ""})
	return {"in": ins, "out": outs}


func _find_pin(pin_list: Array, pin_name: String) -> Dictionary:
	for p_v in pin_list:
		var p: Dictionary = p_v
		if p["name"] == pin_name:
			return p
	return {}


func _connect_error(from_id: String, from_pin: String, to_id: String, to_pin: String) -> String:
	if not has_graph_node(from_id):
		return "unknown node '%s'" % from_id
	if not has_graph_node(to_id):
		return "unknown node '%s'" % to_id
	if from_id == to_id:
		return "a node cannot connect to itself"
	var fp: Dictionary = _find_pin(_pins_for(from_id)["out"], from_pin)
	if fp.is_empty():
		return "node '%s' has no output pin '%s'" % [from_id, from_pin]
	var tp: Dictionary = _find_pin(_pins_for(to_id)["in"], to_pin)
	if tp.is_empty():
		return "node '%s' has no input pin '%s'" % [to_id, to_pin]
	if not Adapters.compatible(kind, fp, tp):
		return "pin types do not match"
	var conns: Array = _model["conns"]
	for c_v in conns:
		var c: Dictionary = c_v
		if c["from"] == from_id and c["from_pin"] == from_pin and c["to"] == to_id and c["to_pin"] == to_pin:
			return "already connected"
	return ""


# ---------------------------------------------------------------- view

func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_toolbar = HBoxContainer.new()
	root.add_child(_toolbar)
	_kind_opt = OptionButton.new()
	for k in Adapters.KINDS:
		_kind_opt.add_item(k)
	_toolbar.add_child(_kind_opt)
	_toolbar.add_child(_make_button("New", _on_new_pressed))
	_add_menu = MenuButton.new()
	_add_menu.text = "Add node"
	_add_menu.get_popup().id_pressed.connect(_on_palette_pressed)
	_toolbar.add_child(_add_menu)
	_undo_btn = _make_button("Undo", undo)
	_redo_btn = _make_button("Redo", redo)
	_toolbar.add_child(_undo_btn)
	_toolbar.add_child(_redo_btn)
	_toolbar.add_child(_make_button("Delete", _on_delete_pressed))
	_toolbar.add_child(_make_button("Set entry", _on_entry_pressed))
	_toolbar.add_child(_make_button("Validate", validate))
	_toolbar.add_child(_make_button("Save...", _on_save_pressed))
	_toolbar.add_child(_make_button("Load...", _on_load_pressed))
	_graph = GraphEdit.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.right_disconnects = true
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)
	_graph.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph.end_node_move.connect(_on_end_node_move)
	root.add_child(_graph)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_log)
	_update_buttons()


func _make_button(text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _populate_palette() -> void:
	var popup: PopupMenu = _add_menu.get_popup()
	popup.clear()
	var types: Array[String] = Adapters.palette(kind)
	for i in types.size():
		popup.add_item(types[i], i)


func _select_kind_option() -> void:
	var idx: int = Adapters.KINDS.find(kind)
	if idx >= 0:
		_kind_opt.select(idx)


func _update_buttons() -> void:
	if _undo_btn != null:
		_undo_btn.disabled = _undo_stack.is_empty()
		_redo_btn.disabled = _redo_stack.is_empty()


func _show_log(errs: Array[String]) -> void:
	if errs.is_empty():
		_log.text = "Valid."
	else:
		_log.text = "\n".join(errs.slice(0, 8))


func _rebuild_view() -> void:
	_view_dirty = false
	_building = true
	_graph.clear_connections()
	for ch in _graph.get_children():
		if ch is GraphNode:
			_graph.remove_child(ch)
			ch.free()
	_gn_by_id.clear()
	_id_by_name.clear()
	var nodes: Dictionary = _model["nodes"]
	for id in nodes:
		var gn: GraphNode = _make_graph_node(str(id))
		_graph.add_child(gn)
		_gn_by_id[str(id)] = gn
		_id_by_name[str(gn.name)] = str(id)
	var conns: Array = _model["conns"]
	for c_v in conns:
		var c: Dictionary = c_v
		var fid: String = str(c["from"])
		var tid: String = str(c["to"])
		if not _gn_by_id.has(fid) or not _gn_by_id.has(tid):
			continue
		var fport: int = _port_index(_pins_for(fid)["out"], str(c["from_pin"]))
		var tport: int = _port_index(_pins_for(tid)["in"], str(c["to_pin"]))
		if fport >= 0 and tport >= 0:
			var fgn: GraphNode = _gn_by_id[fid]
			var tgn: GraphNode = _gn_by_id[tid]
			_graph.connect_node(fgn.name, fport, tgn.name, tport)
	_building = false


func _port_index(pin_list: Array, pin_name: String) -> int:
	for i in pin_list.size():
		var p: Dictionary = pin_list[i]
		if p["name"] == pin_name:
			return i
	return -1


func _make_graph_node(id: String) -> GraphNode:
	var nodes: Dictionary = _model["nodes"]
	var n: Dictionary = nodes[id]
	var params: Dictionary = n["params"]
	var type: String = str(n["type"])
	var pins: Dictionary = _pins_for(id)
	var ins: Array = pins["in"]
	var outs: Array = pins["out"]
	var gn: GraphNode = GraphNode.new()
	_serial += 1
	gn.name = "gn_%d" % _serial
	var meta: Dictionary = _model["meta"]
	var is_entry: bool = Adapters.entry_field(kind) != "" and str(meta.get(Adapters.entry_field(kind), "")) == id
	gn.title = ("* " if is_entry else "") + Adapters.node_title(kind, type, id)
	gn.position_offset = n["pos"]
	gn.set_meta("cg_id", id)
	var rows: int = maxi(ins.size(), outs.size())
	for i in rows:
		var row: HBoxContainer = HBoxContainer.new()
		var left: Label = Label.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var right: Label = Label.new()
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var in_slot: int = 0
		var out_slot: int = 0
		if i < ins.size():
			var ip: Dictionary = ins[i]
			left.text = str(ip["label"])
			in_slot = int(ip["slot"])
		if i < outs.size():
			var op: Dictionary = outs[i]
			right.text = str(op["label"])
			out_slot = int(op["slot"])
		row.add_child(left)
		row.add_child(right)
		gn.add_child(row)
		gn.set_slot(i, i < ins.size(), in_slot, Adapters.pin_color(in_slot), i < outs.size(), out_slot, Adapters.pin_color(out_slot))
	# Parameter fields (defaults shown for keys the asset does not set).
	var keys: Array = params.keys()
	var defaults: Dictionary = Adapters.default_params(kind, type)
	for k in defaults:
		if not keys.has(k):
			keys.append(k)
	for k in keys:
		var key: String = str(k)
		var prow: HBoxContainer = HBoxContainer.new()
		var lab: Label = Label.new()
		lab.text = key
		var le: LineEdit = LineEdit.new()
		le.custom_minimum_size = Vector2(110, 0)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text = Adapters.value_to_text(params[k] if params.has(k) else defaults[k])
		le.text_submitted.connect(_on_param_text.bind(id, key))
		le.focus_exited.connect(_on_param_focus_lost.bind(id, key, le))
		prow.add_child(lab)
		prow.add_child(le)
		gn.add_child(prow)
	var status: Label = Label.new()
	status.name = "StatusLabel"
	status.modulate = Color(0.6, 1.0, 0.6)
	gn.add_child(status)
	_apply_status(gn, id)
	return gn


func _apply_status(gn: GraphNode, id: String) -> void:
	var lab: Label = gn.get_node_or_null("StatusLabel") as Label
	if lab == null:
		return
	var text: String = str(_status.get(id, ""))
	lab.text = text
	lab.visible = text != ""


# ---------------------------------------------------------------- UI callbacks

func _on_new_pressed() -> void:
	new_asset(Adapters.KINDS[_kind_opt.selected])


func _on_palette_pressed(index: int) -> void:
	var types: Array[String] = Adapters.palette(kind)
	if index < 0 or index >= types.size():
		return
	var center: Vector2 = (_graph.scroll_offset + _graph.size * 0.5) / maxf(_graph.zoom, 0.01)
	add_node(types[index], center)


func _on_delete_pressed() -> void:
	remove_nodes(_selected_ids())


func _on_entry_pressed() -> void:
	var sel: Array[String] = _selected_ids()
	if not sel.is_empty():
		set_entry(sel[0])


func _selected_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _gn_by_id:
		var gn: GraphNode = _gn_by_id[id]
		if gn.selected:
			out.append(str(id))
	return out


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var fid: String = str(_id_by_name.get(str(from_node), ""))
	var tid: String = str(_id_by_name.get(str(to_node), ""))
	var fo: Array = _pins_for(fid)["out"]
	var ti: Array = _pins_for(tid)["in"]
	if from_port < 0 or from_port >= fo.size() or to_port < 0 or to_port >= ti.size():
		return
	var err: String = connect_nodes(fid, str((fo[from_port] as Dictionary)["name"]), tid, str((ti[to_port] as Dictionary)["name"]))
	if err != "":
		_log.text = err


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var fid: String = str(_id_by_name.get(str(from_node), ""))
	var tid: String = str(_id_by_name.get(str(to_node), ""))
	var fo: Array = _pins_for(fid)["out"]
	var ti: Array = _pins_for(tid)["in"]
	if from_port < 0 or from_port >= fo.size() or to_port < 0 or to_port >= ti.size():
		return
	disconnect_nodes(fid, str((fo[from_port] as Dictionary)["name"]), tid, str((ti[to_port] as Dictionary)["name"]))


func _on_delete_nodes_request(names: Array[StringName]) -> void:
	var ids: Array[String] = []
	for nm in names:
		var id: String = str(_id_by_name.get(str(nm), ""))
		if id != "":
			ids.append(id)
	remove_nodes(ids)


func _on_end_node_move() -> void:
	if _building:
		return
	var before: Dictionary = _snapshot()
	var nodes: Dictionary = _model["nodes"]
	for id in _gn_by_id:
		var gn: GraphNode = _gn_by_id[id]
		if gn.selected and nodes.has(id):
			var n: Dictionary = nodes[id]
			n["pos"] = gn.position_offset
			n["has_pos"] = true
	_commit("move", before, false)


func _on_param_text(text: String, id: String, key: String) -> void:
	_apply_param_text(id, key, text)


func _on_param_focus_lost(id: String, key: String, le: LineEdit) -> void:
	_apply_param_text(id, key, le.text)


## Skips no-op edits so focusing a field does not materialise a default as an explicit param.
func _apply_param_text(id: String, key: String, text: String) -> void:
	if not has_graph_node(id):
		return
	var value: Variant = Adapters.text_to_value(text)
	var nodes: Dictionary = _model["nodes"]
	var n: Dictionary = nodes[id]
	var p: Dictionary = n["params"]
	if not p.has(key):
		var defs: Dictionary = Adapters.default_params(kind, str(n["type"]))
		if defs.has(key) and typeof(defs[key]) == typeof(value) and hash(defs[key]) == hash(value):
			return
	set_param(id, key, value)


func _on_save_pressed() -> void:
	_open_dialog(true)


func _on_load_pressed() -> void:
	_open_dialog(false)


func _open_dialog(save: bool) -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.access = FileDialog.ACCESS_RESOURCES
		_dialog.add_filter("*.json", "Graph JSON")
		_dialog.file_selected.connect(_on_file_selected)
		add_child(_dialog)
	_dialog_save = save
	_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	if _dialog_save:
		var err: Error = save_json(path)
		_log.text = "Saved %s" % path if err == OK else "Save failed: %s" % error_string(err)
	else:
		_log.text = "Loaded %s" % path if load_json(path) else "Load failed: %s" % path
