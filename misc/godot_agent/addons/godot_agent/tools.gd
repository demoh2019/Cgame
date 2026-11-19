extends RefCounted
## Tool registry: schemas for MCP `tools/list` and the dispatcher for `tools/call`.
## Descriptions are deliberately terse; the DSL syntax lives in INSTRUCTIONS (sent once).

const C = preload("common.gd")
const ApiRef = preload("api_ref.gd")
const SceneEdit = preload("scene_edit.gd")
const ProjectInfo = preload("project_info.gd")
const Proc = preload("proc.gd")

const INSTRUCTIONS := """Godot game-building tools. Paths are res:// (prefix optional). Outputs are compact; errors start with ERR.
Workflow: project -> api (look up classes, never guess) -> write scripts -> edit scenes -> check -> run with expect.
edit ops (one per line, paths relative to scene root, "." = root):
 root Type [Name]            new scene
 + Parent/Name Type k=v ...  add node (Type or @res://scene.tscn); script=res://x.gd first attaches script
 ~ Path k=v ...              set props; vectors 10,20; colors #rrggbb|red; enums by name; res:// loads; sub-resources: shape=new:RectangleShape2D shape.size=32,32
 - Path | mv Path Parent | rename Path Name | conn From sig To method | group Path name
setting ops: set a/b v | main res://s.tscn | autoload N res://x.gd | action name Key... | layer 2d_physics 1 Name
run: inputs "action@from-to" frames (e.g. "ui_right@0-60"); expect = one GDScript expression per line evaluated on scene root (get_node("P").position.x > 50)."""


func _init(addon_dir: String) -> void:
	_proc = Proc.new(addon_dir)

var _proc: Proc
var _api := ApiRef.new()
var _info := ProjectInfo.new()


func list() -> Array:
	return [
		_def("project", "Project overview: settings, autoloads, input actions, file tree.", {
			"dir": _s("subfolder"), "depth": _i("default 3")}),
		_def("api", "Engine class reference. class=?text searches class names. own=false adds inherited members; kinds subset of pmsvk (props,methods,signals,virtuals,constants).", {
			"class": _s(""), "q": _s("member name filter"), "own": _b(""), "kinds": _s("")}, ["class"]),
		_def("outline", "Scene tree with non-default properties, without loading scripts.", {
			"scene": _s("res://x.tscn"), "props": _b("default true")}, ["scene"]),
		_def("edit", "Create/modify a scene with the ops DSL (see instructions). Partial failures are reported per line.", {
			"scene": _s("res://x.tscn"), "ops": _s("ops, one per line"), "show": _b("return outline after")}, ["scene", "ops"]),
		_def("read", "Read a text file. lines=\"a-b\" returns numbered lines.", {
			"path": _s(""), "lines": _s("")}, ["path"]),
		_def("write", "Write a file, or patch it with unique old->new. .gd files are parse-checked.", {
			"path": _s(""), "content": _s("full content"), "old": _s("text to replace"), "new": _s("replacement")}, ["path"]),
		_def("setting", "Project settings ops, one per line (see instructions).", {
			"ops": _s("")}, ["ops"]),
		_def("check", "Parse-check scripts and load-check scenes (all when paths empty). Returns file:line errors.", {
			"paths": _s("space separated, optional")}),
		_def("run", "Run a scene headless (default main) for N frames with scripted input; returns expect results and condensed errors.", {
			"scene": _s(""), "frames": _i("default 120"), "inputs": _s("action@from-to ..."),
			"expect": _s("expressions, one per line"), "watch": _s("expressions to print")}),
	]


static func _s(d: String) -> Dictionary:
	return {"type": "string", "description": d} if d != "" else {"type": "string"}


static func _i(d: String) -> Dictionary:
	return {"type": "integer", "description": d} if d != "" else {"type": "integer"}


static func _b(d: String) -> Dictionary:
	return {"type": "boolean", "description": d} if d != "" else {"type": "boolean"}


static func _def(name: String, desc: String, props: Dictionary, required: Array = []) -> Dictionary:
	var schema := {"type": "object", "properties": props}
	if not required.is_empty():
		schema["required"] = required
	return {"name": name, "description": desc, "inputSchema": schema}


## Returns the text result; errors are strings starting with "ERR".
func call_tool(name: String, a: Dictionary) -> String:
	match name:
		"project":
			return _info.overview(String(a.get("dir", "")), int(a.get("depth", 3)))
		"api":
			return _api.lookup(String(a.get("class", "")), String(a.get("q", "")), bool(a.get("own", true)), String(a.get("kinds", "pmsvk")))
		"outline":
			return SceneEdit.new().outline(String(a.get("scene", "")), bool(a.get("props", true)))
		"edit":
			return SceneEdit.new().edit(String(a.get("scene", "")), String(a.get("ops", "")), bool(a.get("show", false)))
		"read":
			return _info.read(String(a.get("path", "")), String(a.get("lines", "")))
		"write":
			var res := _info.write(String(a.get("path", "")), String(a.get("content", "")), String(a.get("old", "")), String(a.get("new", "")))
			if res.begins_with("ok") and String(a.get("path", "")).ends_with(".gd"):
				var chk := _proc.check(PackedStringArray([C.res_path(String(a.get("path", "")))]))
				if not chk.begins_with("ok"):
					res += "\n" + chk
			return res
		"setting":
			return _info.setting(String(a.get("ops", "")))
		"check":
			return _proc.check(PackedStringArray(String(a.get("paths", "")).split(" ", false)))
		"run":
			return _proc.run(String(a.get("scene", "")), int(a.get("frames", 120)), String(a.get("inputs", "")), String(a.get("expect", "")), String(a.get("watch", "")))
	return "ERR unknown tool " + name
