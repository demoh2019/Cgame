@tool
extends RefCounted
## Tool implementations for the Cgame MCP server. Every tool is `t_<name>(args: Dictionary) -> Dictionary`.
##
## Results are plain Dictionaries serialised as compact JSON by the server. A result containing an
## "error" key is reported as an MCP tool error (isError). A result may contain "_image"
## ({data: base64, mimeType}) which is sent as an image content block, or "_job" (RunJob) for
## long-running work the server polls without blocking the editor.
##
## Edits to the edited scene go through EditorUndoRedoManager, so Ctrl+Z in the editor undoes them.
## Design notes were inspired by public Godot MCP servers (MIT/Apache); no code is copied.

const Lib = preload("res://scripts/tools/agent_lib.gd")
const SHOT_DIR := "user://cgame_mcp/shots"

## Ring buffer of editor-process log lines (filled by the plugin through a Logger).
var log_lines: Array[String] = []


## Background job for blocking subprocess work (test runs) so the editor keeps responding.
class RunJob extends RefCounted:
	var thread: Thread = Thread.new()
	var started_ms: int = Time.get_ticks_msec()

	func start(suites: Array) -> void:
		thread.start(_run.bind(suites))

	func _run(suites: Array) -> Dictionary:
		return Lib.run_tests(suites)

	func finished() -> bool:
		return not thread.is_alive()

	func collect() -> Dictionary:
		var r: Variant = thread.wait_to_finish()
		return r if r is Dictionary else {"error": "test job failed"}


# --------------------------------------------------------------------------------------------
# Schema helpers and tool table
# --------------------------------------------------------------------------------------------

static func _s(desc: String) -> Dictionary:
	return {"type": "string", "description": desc}


static func _i(desc: String) -> Dictionary:
	return {"type": "integer", "description": desc}


static func _b(desc: String) -> Dictionary:
	return {"type": "boolean", "description": desc}


static func _arr(desc: String) -> Dictionary:
	return {"type": "array", "items": {"type": "string"}, "description": desc}


static func _def(tool_name: String, desc: String, props: Dictionary, required: Array, read_only: bool,
		destructive: bool = false) -> Dictionary:
	return {
		"name": tool_name,
		"description": desc,
		"inputSchema": {"type": "object", "properties": props, "required": required},
		"annotations": {"readOnlyHint": read_only, "destructiveHint": destructive, "openWorldHint": false},
	}


func tool_defs() -> Array[Dictionary]:
	var node_path: Dictionary = _s("Node path relative to the edited scene root ('.' or '' = root)")
	var defs: Array[Dictionary] = []
	defs.append(_def("editor_state", "Editor status: version, open scenes, current scene, playing, selection count.", {}, [], true))
	defs.append(_def("scene_tree", "Compact list of nodes of the edited scene ('path [Type] @script').",
		{"root": node_path, "depth": _i("max depth (default 4)"), "filter": _s("keep nodes whose name or type contains this"),
		"limit": _i("max nodes (default 150)"), "offset": _i("skip first N nodes (pagination)")}, [], true))
	defs.append(_def("node_get", "Inspect one node: type, script, groups, children, non-default properties.",
		{"path": node_path, "props": _arr("only these properties"), "all": _b("include default-valued properties"),
		"limit": _i("max properties (default 60)")}, ["path"], true))
	defs.append(_def("node_set_property", "Set a property (undoable). Value may be JSON or a Godot literal string like 'Vector3(1,2,3)' or 'res://x.tres'.",
		{"path": node_path, "property": _s("property name, e.g. 'position' or 'mesh:size'"), "value": {"description": "new value"}},
		["path", "property", "value"], false))
	defs.append(_def("node_create", "Create a node by class or instance a scene under a parent (undoable).",
		{"type": _s("Node class, e.g. 'Node3D'"), "scene": _s("res:// PackedScene to instantiate instead of type"),
		"parent": node_path, "name": _s("node name"), "script": _s("res:// script to attach"),
		"properties": {"type": "object", "description": "initial properties {name: value}"}}, [], false))
	defs.append(_def("node_delete", "Delete a node and its subtree (undoable). The scene root cannot be deleted.",
		{"path": node_path}, ["path"], false, true))
	defs.append(_def("node_move", "Reparent and/or reorder and/or rename a node (undoable).",
		{"path": node_path, "new_parent": _s("new parent path"), "index": _i("child index in parent"), "new_name": _s("rename")},
		["path"], false))
	defs.append(_def("scene_open", "Open a scene file in the editor.", {"path": _s("res://...tscn")}, ["path"], false))
	defs.append(_def("scene_save", "Save the edited scene (or save as another path).", {"path": _s("optional res:// path for save-as")}, [], false))
	defs.append(_def("selection_get", "Paths of the currently selected nodes.", {}, [], true))
	defs.append(_def("selection_set", "Select nodes by path (replaces selection).", {"paths": _arr("node paths")}, ["paths"], false))
	defs.append(_def("find_nodes", "Find nodes in the edited scene by type, name substring and/or group.",
		{"type": _s("class name, inherited classes match too"), "name": _s("name substring"), "group": _s("group name"),
		"under": node_path, "limit": _i("default 100")}, [], true))
	defs.append(_def("resource_inspect", "Load a resource (res://) or read a node's resource property and list its properties.",
		{"path": _s("res:// resource path"), "node": node_path, "property": _s("node property holding the resource"),
		"limit": _i("max properties (default 60)")}, [], true))
	defs.append(_def("script_check", "Parse a GDScript (disk content or given source); returns errors with line numbers. Warnings are errors here.",
		{"path": _s("res:// script"), "source": _s("source text instead of the file")}, [], true))
	defs.append(_def("check_scripts", "Parse-check many scripts: paths, directories or 'all'. Compact error list.",
		{"paths": _arr("res:// files/dirs or ['all']"), "max_errors": _i("default 100")}, [], true))
	defs.append(_def("class_docs", "ClassDB reflection (methods, properties, signals, constants) for a native class, or the public API of a script under scripts/.",
		{"class": _s("ClassDB class or script name, e.g. 'Node3D' or 'crowd_avoidance'"), "filter": _s("member name substring"),
		"limit": _i("default 80")}, ["class"], true))
	defs.append(_def("classes", "List ClassDB class names containing a filter.", {"filter": _s("substring"), "limit": _i("default 60")}, [], true))
	defs.append(_def("project_search", "Limited grep over res:// (gd, md, tscn, tres, cfg, json, gdshader).",
		{"pattern": _s("text or regex"), "regex": _b("treat pattern as regex"), "ext": _s("only this extension, e.g. '.gd'"),
		"dir": _s("res:// subdir (default res://)"), "limit": _i("default 40")}, ["pattern"], true))
	defs.append(_def("find_symbol", "Where is a func/const/class/signal defined? Searches scripts, addons, tests and modules/cgame_* C++.",
		{"symbol": _s("identifier"), "limit": _i("default 40")}, ["symbol"], true))
	defs.append(_def("project_map", "Compact project map: script folders, addons, cgame modules, test suite counts.", {"full": _b("list all suites")}, [], true))
	defs.append(_def("native_status", "Which modules/cgame_* native classes exist in this editor binary and which script facades fall back to GDScript.", {}, [], true))
	defs.append(_def("run_scene", "Play a scene in the editor.", {"which": _s("'current' (default), 'main', or a res:// scene path")}, [], false))
	defs.append(_def("stop_scene", "Stop the running scene.", {}, [], false))
	defs.append(_def("screenshot", "Save a screenshot to user://cgame_mcp/shots and return its path; optional small base64 JPEG thumbnail.",
		{"target": _s("'editor' (default), 'viewport3d', 'viewport2d', or 'screen' (OS screen incl. running game window)"),
		"max_size": _i("max pixel side of saved file (default 1280)"), "thumbnail": _b("also return a 320px JPEG image block")}, [], true))
	defs.append(_def("logs_tail", "Last N lines of the editor Output panel (includes running-game output) or the editor-process log ring.",
		{"lines": _i("default 50"), "filter": _s("case-insensitive substring"), "level": _s("'all' (default), 'error', 'warning'"),
		"source": _s("'output' (default) or 'editor'")}, [], true))
	defs.append(_def("run_tests", "Run headless test suites in a child process (names like 'test_gear_durability', or 'all'); returns totals and failures.",
		{"suites": _arr("suite names or ['all']")}, ["suites"], true))
	defs.append(_def("perf_snapshot", "Editor-process Performance monitors (fps, frame ms, memory, objects, draw calls).", {}, [], true))
	return defs


func call_tool(tool_name: String, args: Dictionary) -> Dictionary:
	var method: String = "t_" + tool_name
	if not has_method(method):
		return {"error": "unknown tool '%s'" % tool_name}
	var r: Variant = call(method, args)
	return r if r is Dictionary else {"error": "tool returned no result"}


# --------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------

func _root() -> Node:
	return EditorInterface.get_edited_scene_root()


func _resolve(path: String) -> Node:
	var root: Node = _root()
	if root == null:
		return null
	var p: String = path.strip_edges()
	if p == "" or p == "." or p == "/" or p == str(root.name):
		return root
	p = p.trim_prefix("/").trim_prefix(str(root.name) + "/")
	return root.get_node_or_null(NodePath(p))


func _rel(node: Node) -> String:
	var root: Node = _root()
	return "." if node == root else str(root.get_path_to(node))


static func _err(msg: String) -> Dictionary:
	return {"error": msg}


func _need_scene() -> Dictionary:
	return _err("no scene is open in the editor (use scene_open)")


static func ser(v: Variant, depth: int = 0) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return v
		TYPE_FLOAT:
			var f: float = v
			return f if is_finite(f) else str(f)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v)
		TYPE_OBJECT:
			if v == null or not is_instance_valid(v):
				return null
			if v is Resource:
				var res: Resource = v
				return res.resource_path if not res.resource_path.is_empty() else "<%s>" % res.get_class()
			if v is Node:
				return "node:" + str((v as Node).name)
			return "<%s>" % (v as Object).get_class()
		TYPE_ARRAY:
			var a: Array = v
			if depth > 2 or a.size() > 24:
				return "Array(%d)" % a.size()
			var out: Array = []
			for x: Variant in a:
				out.append(ser(x, depth + 1))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if depth > 2 or d.size() > 24:
				return "Dictionary(%d)" % d.size()
			var outd: Dictionary = {}
			for k: Variant in d:
				outd[str(k)] = ser(d[k], depth + 1)
			return outd
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
		TYPE_PACKED_COLOR_ARRAY:
			var s: String = var_to_str(v)
			return s if s.length() <= 160 else "%s(%d items)" % [type_string(typeof(v)), int(v.size())]
		_:
			return var_to_str(v)


## Converts an agent-supplied JSON value to the type of the property.
static func parse_value(v: Variant, prop_type: int) -> Variant:
	if v is String or v is StringName:
		var s: String = str(v)
		match prop_type:
			TYPE_STRING:
				return s
			TYPE_STRING_NAME:
				return StringName(s)
			TYPE_NODE_PATH:
				return NodePath(s)
			TYPE_OBJECT:
				if s.begins_with("res://") or s.begins_with("uid://"):
					return load(s)
				return null if s == "null" or s.is_empty() else s
			_:
				var parsed: Variant = str_to_var(s)
				if parsed != null or s == "null":
					return parsed
				return s
	if v is Array:
		var arr: Array = v
		match prop_type:
			TYPE_VECTOR2:
				if arr.size() == 2:
					return Vector2(float(arr[0]), float(arr[1]))
			TYPE_VECTOR2I:
				if arr.size() == 2:
					return Vector2i(int(arr[0]), int(arr[1]))
			TYPE_VECTOR3:
				if arr.size() == 3:
					return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
			TYPE_VECTOR3I:
				if arr.size() == 3:
					return Vector3i(int(arr[0]), int(arr[1]), int(arr[2]))
			TYPE_VECTOR4:
				if arr.size() == 4:
					return Vector4(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
			TYPE_COLOR:
				if arr.size() == 3:
					return Color(float(arr[0]), float(arr[1]), float(arr[2]))
				if arr.size() == 4:
					return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
	if prop_type == TYPE_INT or prop_type == TYPE_FLOAT or prop_type == TYPE_BOOL:
		return type_convert(v, prop_type)
	return v


static func _prop_type(obj: Object, prop: String) -> int:
	var base: String = prop.split(":")[0]
	for p: Dictionary in obj.get_property_list():
		if p["name"] == base:
			return int(p["type"]) if base == prop else TYPE_NIL
	return TYPE_NIL


static func _page(items: Array, offset: int, limit: int) -> Array:
	return items.slice(offset, offset + limit)


# --------------------------------------------------------------------------------------------
# State / scene
# --------------------------------------------------------------------------------------------

func t_editor_state(_a: Dictionary) -> Dictionary:
	var root: Node = _root()
	var sel: int = EditorInterface.get_selection().get_selected_nodes().size()
	return {
		"engine": str(Engine.get_version_info().get("string", "")),
		"project": str(ProjectSettings.get_setting("application/config/name", "")),
		"scene": root.scene_file_path if root != null else "",
		"root": str(root.name) if root != null else "",
		"open_scenes": EditorInterface.get_open_scenes(),
		"playing": EditorInterface.is_playing_scene(),
		"playing_scene": EditorInterface.get_playing_scene(),
		"selected": sel,
		"headless": DisplayServer.get_name() == "headless",
	}


func t_scene_tree(a: Dictionary) -> Dictionary:
	var root: Node = _root()
	if root == null:
		return _need_scene()
	var start: Node = _resolve(str(a.get("root", "")))
	if start == null:
		return _err("root not found: %s" % str(a.get("root", "")))
	var max_depth: int = int(a.get("depth", 4))
	var flt: String = str(a.get("filter", "")).to_lower()
	var limit: int = clampi(int(a.get("limit", 150)), 1, 1000)
	var offset: int = maxi(int(a.get("offset", 0)), 0)
	var lines: Array[String] = []
	var stack: Array = [[start, 0]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var d: int = int(item[1])
		var type_name: String = n.get_class()
		if flt.is_empty() or str(n.name).to_lower().contains(flt) or type_name.to_lower().contains(flt):
			var line: String = "%s [%s]" % [_rel(n), type_name]
			var scr: Variant = n.get_script()
			if scr is Script:
				line += " @" + (scr as Script).resource_path.get_file()
			if d >= max_depth and n.get_child_count() > 0:
				line += " +%d" % n.get_child_count()
			lines.append(line)
		if d < max_depth:
			var kids: Array[Node] = n.get_children()
			for k in range(kids.size() - 1, -1, -1):
				stack.append([kids[k], d + 1])
	var shown: Array = _page(lines, offset, limit)
	var result: Dictionary = {"scene": root.scene_file_path, "total": lines.size(), "nodes": shown}
	if offset + limit < lines.size():
		result["next_offset"] = offset + limit
	return result


func t_node_get(a: Dictionary) -> Dictionary:
	var node: Node = _resolve(str(a.get("path", "")))
	if node == null:
		return _err("node not found: %s" % str(a.get("path", "")))
	var limit: int = clampi(int(a.get("limit", 60)), 1, 300)
	var want: Array = a.get("props", [])
	var props: Dictionary = {}
	var cls: String = node.get_class()
	if not want.is_empty():
		for pn: Variant in want:
			props[str(pn)] = ser(node.get(str(pn)))
	else:
		for p: Dictionary in node.get_property_list():
			var usage: int = int(p["usage"])
			var pname: String = str(p["name"])
			if (usage & PROPERTY_USAGE_EDITOR) == 0 or (usage & PROPERTY_USAGE_CATEGORY) != 0 \
					or (usage & PROPERTY_USAGE_GROUP) != 0 or pname == "script":
				continue
			var val: Variant = node.get(pname)
			if not bool(a.get("all", false)) \
					and typeof(val) == typeof(ClassDB.class_get_property_default_value(cls, pname)) \
					and val == ClassDB.class_get_property_default_value(cls, pname):
				continue
			props[pname] = ser(val)
			if props.size() >= limit:
				break
	var kids: Array[String] = []
	for c in node.get_children():
		if kids.size() < 40:
			kids.append("%s [%s]" % [c.name, c.get_class()])
	var scr: Variant = node.get_script()
	return {"path": _rel(node), "type": cls, "script": (scr as Script).resource_path if scr is Script else "",
		"scene_file": node.scene_file_path, "groups": node.get_groups().map(func(g: StringName) -> String: return str(g)),
		"child_count": node.get_child_count(), "children": kids, "props": props}


func _set_prop_undoable(node: Node, prop: String, value: Variant) -> void:
	var ur: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	var old: Variant = node.get_indexed(prop)
	ur.create_action("MCP: set %s.%s" % [node.name, prop], UndoRedo.MERGE_DISABLE, _root())
	ur.add_do_property(node, prop, value)
	ur.add_undo_property(node, prop, old)
	ur.commit_action()


func t_node_set_property(a: Dictionary) -> Dictionary:
	var node: Node = _resolve(str(a.get("path", "")))
	if node == null:
		return _err("node not found: %s" % str(a.get("path", "")))
	var prop: String = str(a.get("property", ""))
	var base: String = prop.split(":")[0]
	var known: bool = false
	for p: Dictionary in node.get_property_list():
		if p["name"] == base:
			known = true
			break
	if not known:
		return _err("%s has no property '%s' (use node_get to list)" % [node.get_class(), base])
	var ptype: int = _prop_type(node, prop)
	var value: Variant = parse_value(a.get("value"), ptype)
	_set_prop_undoable(node, prop, value)
	return {"ok": true, "path": _rel(node), "property": prop, "value": ser(node.get_indexed(prop))}


func _op_add(parent: Node, node: Node, root: Node, index: int) -> void:
	parent.add_child(node, true)
	node.owner = root
	if index >= 0:
		parent.move_child(node, mini(index, parent.get_child_count() - 1))


func _op_remove(parent: Node, node: Node) -> void:
	if node.get_parent() == parent:
		parent.remove_child(node)


func _op_restore(parent: Node, node: Node, _scene_root: Node, index: int, owners: Dictionary) -> void:
	parent.add_child(node, true)
	parent.move_child(node, mini(index, parent.get_child_count() - 1))
	for n: Node in owners:
		if is_instance_valid(n):
			n.owner = owners[n]


func _collect_owners(node: Node, out: Dictionary) -> void:
	out[node] = node.owner
	for c in node.get_children():
		_collect_owners(c, out)


func t_node_create(a: Dictionary) -> Dictionary:
	var root: Node = _root()
	if root == null:
		return _need_scene()
	var parent: Node = _resolve(str(a.get("parent", "")))
	if parent == null:
		return _err("parent not found: %s" % str(a.get("parent", "")))
	var node: Node = null
	var scene_path: String = str(a.get("scene", ""))
	if not scene_path.is_empty():
		var ps: PackedScene = load(scene_path) as PackedScene
		if ps == null:
			return _err("cannot load PackedScene: " + scene_path)
		node = ps.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	else:
		var type_name: String = str(a.get("type", ""))
		if type_name.is_empty():
			return _err("give 'type' or 'scene'")
		if not ClassDB.class_exists(type_name) or not ClassDB.is_parent_class(type_name, "Node") \
				or not ClassDB.can_instantiate(type_name):
			return _err("'%s' is not an instantiable Node class" % type_name)
		node = ClassDB.instantiate(type_name) as Node
	if node == null:
		return _err("instantiation failed")
	var script_path: String = str(a.get("script", ""))
	if not script_path.is_empty():
		var scr: Script = load(script_path) as Script
		if scr == null:
			node.free()
			return _err("cannot load script: " + script_path)
		node.set_script(scr)
	if a.has("name") and not str(a["name"]).is_empty():
		node.name = str(a["name"])
	var bad: Array[String] = []
	var init: Dictionary = a.get("properties", {})
	for k: Variant in init:
		var pn: String = str(k)
		if _prop_type(node, pn) == TYPE_NIL and not pn.contains(":"):
			bad.append(pn)
			continue
		node.set_indexed(pn, parse_value(init[k], _prop_type(node, pn)))
	var ur: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	ur.create_action("MCP: create %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(self, &"_op_add", parent, node, root, -1)
	ur.add_do_reference(node)
	ur.add_undo_method(self, &"_op_remove", parent, node)
	ur.commit_action()
	var result: Dictionary = {"ok": true, "path": _rel(node), "type": node.get_class()}
	if not bad.is_empty():
		result["unknown_properties"] = bad
	return result


func t_node_delete(a: Dictionary) -> Dictionary:
	var root: Node = _root()
	var node: Node = _resolve(str(a.get("path", "")))
	if node == null:
		return _err("node not found: %s" % str(a.get("path", "")))
	if node == root:
		return _err("refusing to delete the scene root")
	var parent: Node = node.get_parent()
	var owners: Dictionary = {}
	_collect_owners(node, owners)
	var idx: int = node.get_index()
	var label: String = _rel(node)
	var ur: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	ur.create_action("MCP: delete %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(self, &"_op_remove", parent, node)
	ur.add_undo_method(self, &"_op_restore", parent, node, root, idx, owners)
	ur.add_undo_reference(node)
	ur.commit_action()
	return {"ok": true, "deleted": label}


func _op_reparent(node: Node, new_parent: Node, index: int) -> void:
	if node.get_parent() != new_parent:
		node.reparent(new_parent, true)
	if index >= 0:
		new_parent.move_child(node, mini(index, new_parent.get_child_count() - 1))


func t_node_move(a: Dictionary) -> Dictionary:
	var root: Node = _root()
	var node: Node = _resolve(str(a.get("path", "")))
	if node == null:
		return _err("node not found: %s" % str(a.get("path", "")))
	if node == root:
		return _err("cannot move the scene root")
	var old_parent: Node = node.get_parent()
	var old_index: int = node.get_index()
	var new_parent: Node = old_parent
	if a.has("new_parent"):
		new_parent = _resolve(str(a["new_parent"]))
		if new_parent == null:
			return _err("new_parent not found: %s" % str(a["new_parent"]))
		if new_parent == node or node.is_ancestor_of(new_parent):
			return _err("cannot reparent a node under itself")
	var index: int = int(a.get("index", -1))
	var old_name: String = str(node.name)
	var ur: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	ur.create_action("MCP: move %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(self, &"_op_reparent", node, new_parent, index)
	ur.add_undo_method(self, &"_op_reparent", node, old_parent, old_index)
	if a.has("new_name") and not str(a["new_name"]).is_empty():
		ur.add_do_property(node, &"name", str(a["new_name"]))
		ur.add_undo_property(node, &"name", old_name)
	ur.commit_action()
	return {"ok": true, "path": _rel(node)}


func t_scene_open(a: Dictionary) -> Dictionary:
	var path: String = str(a.get("path", ""))
	if not FileAccess.file_exists(path):
		return _err("file not found: " + path)
	EditorInterface.open_scene_from_path(path)
	return {"ok": true, "opened": path}


func t_scene_save(a: Dictionary) -> Dictionary:
	if _root() == null:
		return _need_scene()
	var path: String = str(a.get("path", ""))
	if path.is_empty():
		var err: int = EditorInterface.save_scene()
		if err != OK:
			return _err("save failed: %s" % error_string(err))
		return {"ok": true, "path": _root().scene_file_path}
	EditorInterface.save_scene_as(path)
	return {"ok": true, "path": path}


func t_selection_get(_a: Dictionary) -> Dictionary:
	if _root() == null:
		return _need_scene()
	var out: Array[String] = []
	for n: Node in EditorInterface.get_selection().get_selected_nodes():
		out.append(_rel(n))
	return {"selected": out}


func t_selection_set(a: Dictionary) -> Dictionary:
	if _root() == null:
		return _need_scene()
	var sel: EditorSelection = EditorInterface.get_selection()
	sel.clear()
	var missing: Array[String] = []
	for p: Variant in a.get("paths", []):
		var n: Node = _resolve(str(p))
		if n == null:
			missing.append(str(p))
		else:
			sel.add_node(n)
	var result: Dictionary = {"ok": missing.is_empty(), "selected": sel.get_selected_nodes().size()}
	if not missing.is_empty():
		result["missing"] = missing
	return result


func t_find_nodes(a: Dictionary) -> Dictionary:
	var root: Node = _root()
	if root == null:
		return _need_scene()
	var start: Node = _resolve(str(a.get("under", "")))
	if start == null:
		return _err("'under' not found")
	var type_name: String = str(a.get("type", ""))
	var name_part: String = str(a.get("name", "")).to_lower()
	var group: String = str(a.get("group", ""))
	var limit: int = clampi(int(a.get("limit", 100)), 1, 1000)
	var out: Array[String] = []
	var total: int = 0
	var stack: Array[Node] = [start]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var ok: bool = true
		if not type_name.is_empty() and not n.is_class(type_name):
			ok = false
		if ok and not name_part.is_empty() and not str(n.name).to_lower().contains(name_part):
			ok = false
		if ok and not group.is_empty() and not n.is_in_group(group):
			ok = false
		if ok and (not type_name.is_empty() or not name_part.is_empty() or not group.is_empty()):
			total += 1
			if out.size() < limit:
				out.append("%s [%s]" % [_rel(n), n.get_class()])
		var kids: Array[Node] = n.get_children()
		for k in range(kids.size() - 1, -1, -1):
			stack.append(kids[k])
	return {"total": total, "nodes": out, "truncated": total > out.size()}


func t_resource_inspect(a: Dictionary) -> Dictionary:
	var res: Resource = null
	var label: String = str(a.get("path", ""))
	if a.has("node"):
		var node: Node = _resolve(str(a["node"]))
		if node == null:
			return _err("node not found")
		var v: Variant = node.get(str(a.get("property", "")))
		res = v as Resource
		label = "%s.%s" % [a["node"], a.get("property", "")]
	elif not label.is_empty():
		if not ResourceLoader.exists(label):
			return _err("resource not found: " + label)
		res = load(label)
	if res == null:
		return _err("no resource (give 'path' or 'node'+'property')")
	var limit: int = clampi(int(a.get("limit", 60)), 1, 300)
	var props: Dictionary = {}
	for p: Dictionary in res.get_property_list():
		var usage: int = int(p["usage"])
		if (usage & PROPERTY_USAGE_EDITOR) == 0 or (usage & PROPERTY_USAGE_CATEGORY) != 0 or (usage & PROPERTY_USAGE_GROUP) != 0:
			continue
		props[str(p["name"])] = ser(res.get(str(p["name"])))
		if props.size() >= limit:
			break
	return {"resource": label, "type": res.get_class(), "path": res.resource_path, "props": props}


# --------------------------------------------------------------------------------------------
# Code intelligence (shared with agent_cli.gd through agent_lib.gd)
# --------------------------------------------------------------------------------------------

func t_script_check(a: Dictionary) -> Dictionary:
	if a.has("source"):
		var cap: Lib.ErrorCapture = Lib.ErrorCapture.new()
		OS.add_logger(cap)
		var s: GDScript = GDScript.new()
		s.source_code = str(a["source"])
		var err: int = s.reload()
		OS.remove_logger(cap)
		var errors: Array[Dictionary] = []
		for it: Dictionary in cap.items:
			errors.append({"line": it["line"], "message": str(it["message"]).left(300)})
		return {"ok": err == OK and errors.is_empty(), "errors": errors}
	var path: String = str(a.get("path", ""))
	if path.is_empty():
		return _err("give 'path' or 'source'")
	return Lib.check_script(path)


func t_check_scripts(a: Dictionary) -> Dictionary:
	var paths: Array = a.get("paths", ["all"])
	return Lib.check_scripts(paths if not paths.is_empty() else ["all"], int(a.get("max_errors", 100)))


func t_class_docs(a: Dictionary) -> Dictionary:
	return Lib.api(str(a.get("class", "")), str(a.get("filter", "")), int(a.get("limit", 80)))


func t_classes(a: Dictionary) -> Dictionary:
	return Lib.classes(str(a.get("filter", "")), int(a.get("limit", 60)))


func t_project_search(a: Dictionary) -> Dictionary:
	return Lib.search_project(str(a.get("pattern", "")), str(a.get("ext", "")), int(a.get("limit", 40)),
		bool(a.get("regex", false)), str(a.get("dir", "res://")))


func t_find_symbol(a: Dictionary) -> Dictionary:
	return Lib.find_symbol(str(a.get("symbol", "")), int(a.get("limit", 40)))


func t_project_map(a: Dictionary) -> Dictionary:
	return Lib.project_map(bool(a.get("full", false)))


func t_native_status(_a: Dictionary) -> Dictionary:
	return Lib.native_status()


func t_run_tests(a: Dictionary) -> Dictionary:
	var suites: Array = a.get("suites", ["all"])
	var job: RunJob = RunJob.new()
	job.start(suites if not suites.is_empty() else ["all"])
	return {"_job": job}


# --------------------------------------------------------------------------------------------
# Run / observe
# --------------------------------------------------------------------------------------------

func t_run_scene(a: Dictionary) -> Dictionary:
	var which: String = str(a.get("which", "current"))
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	match which:
		"current":
			if _root() == null:
				return _need_scene()
			EditorInterface.play_current_scene()
		"main":
			EditorInterface.play_main_scene()
		_:
			if not FileAccess.file_exists(which):
				return _err("scene not found: " + which)
			EditorInterface.play_custom_scene(which)
	return {"ok": true, "playing": which}


func t_stop_scene(_a: Dictionary) -> Dictionary:
	var was: bool = EditorInterface.is_playing_scene()
	if was:
		EditorInterface.stop_playing_scene()
	return {"ok": true, "was_playing": was}


func t_screenshot(a: Dictionary) -> Dictionary:
	var target: String = str(a.get("target", "editor"))
	var img: Image = null
	match target:
		"editor":
			var tex: ViewportTexture = EditorInterface.get_base_control().get_viewport().get_texture()
			img = tex.get_image() if tex != null else null
		"viewport3d":
			img = EditorInterface.get_editor_viewport_3d(0).get_texture().get_image()
		"viewport2d":
			img = EditorInterface.get_editor_viewport_2d().get_texture().get_image()
		"screen", "game":
			img = DisplayServer.screen_get_image(0)
		_:
			return _err("unknown target '%s'" % target)
	if img == null or img.is_empty():
		return _err("no image available (headless editor or no rendering device); try target 'screen' or run a windowed editor")
	var max_side: int = clampi(int(a.get("max_size", 1280)), 64, 4096)
	if maxi(img.get_width(), img.get_height()) > max_side:
		var scale: float = float(max_side) / float(maxi(img.get_width(), img.get_height()))
		img.resize(maxi(1, roundi(img.get_width() * scale)), maxi(1, roundi(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var path: String = "%s/shot_%d.png" % [SHOT_DIR, Time.get_ticks_msec()]
	img.save_png(path)
	_prune_shots(20)
	var result: Dictionary = {"path": ProjectSettings.globalize_path(path), "width": img.get_width(), "height": img.get_height(), "target": target}
	if bool(a.get("thumbnail", false)):
		var th: Image = img.duplicate()
		if maxi(th.get_width(), th.get_height()) > 320:
			var sc: float = 320.0 / float(maxi(th.get_width(), th.get_height()))
			th.resize(maxi(1, roundi(th.get_width() * sc)), maxi(1, roundi(th.get_height() * sc)), Image.INTERPOLATE_BILINEAR)
		th.convert(Image.FORMAT_RGB8)
		result["_image"] = {"data": Marshalls.raw_to_base64(th.save_jpg_to_buffer(0.7)), "mimeType": "image/jpeg"}
	return result


func _prune_shots(keep: int) -> void:
	var files: Array = Array(DirAccess.get_files_at(SHOT_DIR))
	files.sort()
	while files.size() > keep:
		DirAccess.remove_absolute(SHOT_DIR.path_join(str(files.pop_front())))


func _find_by_class(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children(true):
		var r: Node = _find_by_class(c, cls)
		if r != null:
			return r
	return null


func _find_rich_text(node: Node) -> RichTextLabel:
	if node is RichTextLabel:
		return node as RichTextLabel
	for c in node.get_children(true):
		var r: RichTextLabel = _find_rich_text(c)
		if r != null:
			return r
	return null


func t_logs_tail(a: Dictionary) -> Dictionary:
	var n: int = clampi(int(a.get("lines", 50)), 1, 500)
	var flt: String = str(a.get("filter", "")).to_lower()
	var level: String = str(a.get("level", "all"))
	var source: String = str(a.get("source", "output"))
	var lines: Array[String] = []
	var used: String = "editor"
	if source == "output":
		var log_node: Node = _find_by_class(EditorInterface.get_base_control(), "EditorLog")
		var rtl: RichTextLabel = _find_rich_text(log_node) if log_node != null else null
		if rtl != null:
			lines.assign(Array(rtl.get_parsed_text().split("\n")))
			used = "output"
	if used == "editor":
		lines = log_lines.duplicate()
	var out: Array[String] = []
	for l in lines:
		var low: String = l.to_lower()
		if l.strip_edges().is_empty():
			continue
		if not flt.is_empty() and not low.contains(flt):
			continue
		if level == "error" and not (low.contains("error") or low.begins_with("[err")):
			continue
		if level == "warning" and not (low.contains("warning") or low.contains("error") or low.begins_with("[warn") or low.begins_with("[err")):
			continue
		out.append(l.left(400))
	var tail: Array = out.slice(maxi(0, out.size() - n))
	return {"source": used, "total_matching": out.size(), "lines": tail}


func t_perf_snapshot(_a: Dictionary) -> Dictionary:
	var m: Dictionary = {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
	}
	for cn: StringName in Performance.get_custom_monitor_names():
		m["custom/" + str(cn)] = Performance.get_custom_monitor(cn)
	return {"scope": "editor process (not the running game)", "monitors": m}


# --------------------------------------------------------------------------------------------
# MCP resources: docs/cgame/*.md, AGENTS.md, CLAUDE.md
# --------------------------------------------------------------------------------------------

func list_resources() -> Array[Dictionary]:
	var repo: String = Lib.repo_dir()
	var out: Array[Dictionary] = []
	for f in ["AGENTS.md", "CLAUDE.md"]:
		if FileAccess.file_exists(repo.path_join(f)):
			out.append({"uri": "cgame://" + f, "name": f, "mimeType": "text/markdown",
				"description": "Project instructions for AI agents" if f == "AGENTS.md" else "Claude-specific notes"})
	var docs: String = repo.path_join("docs/cgame")
	var da: DirAccess = DirAccess.open(docs)
	if da != null:
		var files: Array = Array(da.get_files())
		files.sort()
		for f: String in files:
			if f.ends_with(".md"):
				out.append({"uri": "cgame://docs/" + f, "name": "docs/cgame/" + f, "mimeType": "text/markdown"})
	return out


func read_resource(uri: String) -> Dictionary:
	if not uri.begins_with("cgame://"):
		return {}
	var rel: String = uri.trim_prefix("cgame://")
	if rel.contains("..") or rel.begins_with("/") or not rel.ends_with(".md"):
		return {}
	var allowed: bool = rel == "AGENTS.md" or rel == "CLAUDE.md" or (rel.begins_with("docs/") and rel.count("/") == 1)
	if not allowed:
		return {}
	var path: String = Lib.repo_dir().path_join("docs/cgame" if rel.begins_with("docs/") else "").path_join(rel.get_file())
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.length() > 60000:
		text = text.left(60000) + "\n...[truncated]"
	return {"uri": uri, "mimeType": "text/markdown", "text": text}
