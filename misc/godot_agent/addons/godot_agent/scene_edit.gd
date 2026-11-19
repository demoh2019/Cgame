extends RefCounted
## Compact scene editing DSL and scene outlines.
##
## One line per operation, paths are relative to the scene root ("." is the root):
##   root Type [Name] [k=v ...]       create a new scene (only when the file does not exist)
##   + Parent/Name Type [k=v ...]     add a node          (Type may be @res://scene.tscn to instance)
##   ~ Path k=v [k=v ...]             set properties      (sub-resource props: shape.size=8,8)
##   - Path                           delete a node
##   mv Path NewParent                reparent             rename Path NewName
##   conn From signal To method       persistent signal connection
##   group Path name                  add to a group

const C = preload("common.gd")

var _root: Node
var _errors: PackedStringArray = []


func edit(scene_path: String, ops: String, show: bool = false) -> String:
	var path := C.res_path(scene_path)
	if path.is_empty() or not path.ends_with(".tscn"):
		return "ERR scene must be a res:// path ending in .tscn"
	var exists := FileAccess.file_exists(path)
	if exists:
		var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if packed == null:
			return "ERR cannot load " + path
		_root = packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
		if _root == null:
			return "ERR cannot instantiate " + path
	var n_ops := 0
	var line_no := 0
	for raw_line in ops.split("\n"):
		line_no += 1
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var err := _apply(C.tokenize(line))
		n_ops += 1
		if err != "":
			_errors.append("L%d %s" % [line_no, err])
	if _root == null:
		return "ERR scene has no root; start with: root Node2D Main\n" + "\n".join(_errors)
	var count := _count(_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var out_scene := PackedScene.new()
	var perr := out_scene.pack(_root)
	if perr != OK:
		_root.free()
		return "ERR pack failed (%s)" % error_string(perr)
	perr = ResourceSaver.save(out_scene, path)
	_root.free()
	_root = null
	if perr != OK:
		return "ERR save failed (%s)" % error_string(perr)
	var res := "ok %d ops, %d nodes -> %s" % [n_ops, count, path]
	if not _errors.is_empty():
		res += "\n%d failed:\n%s" % [_errors.size(), "\n".join(_errors)]
	if show:
		res += "\n" + outline(path)
	return res


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _find(path: String) -> Node:
	if _root == null:
		return null
	if path == "." or path.is_empty():
		return _root
	return _root.get_node_or_null(path)


func _apply(t: PackedStringArray) -> String:
	var cmd := t[0]
	match cmd:
		"root":
			if _root != null:
				return "root exists"
			if t.size() < 2:
				return "usage: root Type [Name]"
			var node: Variant = _make(t[1])
			if node is String:
				return node
			var name := "Root"
			var kvs: Array = []
			for i in range(2, t.size()):
				var kv := C.split_kv(t[i])
				if kv.is_empty():
					name = t[i]
				else:
					kvs.append(kv)
			(node as Node).name = name
			_root = node
			return _set_props(_root, kvs)
		"+":
			if _root == null:
				return "no root yet"
			if t.size() < 3:
				return "usage: + Parent/Name Type [k=v]"
			var full := t[1]
			var slash := full.rfind("/")
			var parent_path := "." if slash < 0 else full.substr(0, slash)
			var nname := full if slash < 0 else full.substr(slash + 1)
			var parent := _find(parent_path)
			if parent == null:
				return "no parent '%s'" % parent_path
			if parent.get_node_or_null(nname) != null:
				return "'%s' exists" % full
			var made: Variant = _make(t[2])
			if made is String:
				return made
			var nn := made as Node
			nn.name = nname
			parent.add_child(nn)
			nn.owner = _root
			var kvs: Array = []
			for i in range(3, t.size()):
				var kv := C.split_kv(t[i])
				if kv.is_empty():
					return "bad arg '%s' (expected k=v)" % t[i]
				kvs.append(kv)
			return _set_props(nn, kvs)
		"~":
			if t.size() < 3:
				return "usage: ~ Path k=v"
			var target := _find(t[1])
			if target == null:
				return "no node '%s'" % t[1]
			var kvs: Array = []
			for i in range(2, t.size()):
				var kv := C.split_kv(t[i])
				if kv.is_empty():
					return "bad arg '%s' (expected k=v)" % t[i]
				kvs.append(kv)
			return _set_props(target, kvs)
		"-":
			if t.size() < 2:
				return "usage: - Path"
			var victim := _find(t[1])
			if victim == null:
				return "no node '%s'" % t[1]
			if victim == _root:
				return "cannot delete root"
			victim.get_parent().remove_child(victim)
			victim.free()
			return ""
		"mv":
			if t.size() < 3:
				return "usage: mv Path NewParent"
			var moved := _find(t[1])
			var np := _find(t[2])
			if moved == null or np == null or moved == _root:
				return "bad mv paths"
			if np == moved or moved.is_ancestor_of(np):
				return "cannot move into itself"
			moved.reparent(np, true)
			return ""
		"rename":
			if t.size() < 3:
				return "usage: rename Path NewName"
			var rn := _find(t[1])
			if rn == null:
				return "no node '%s'" % t[1]
			rn.name = t[2]
			return ""
		"conn":
			if t.size() < 5:
				return "usage: conn From signal To method"
			var from := _find(t[1])
			var to := _find(t[3])
			if from == null or to == null:
				return "bad conn paths"
			if not from.has_signal(t[2]):
				return "%s has no signal '%s'" % [from.get_class(), t[2]]
			var cb := Callable(to, t[4])
			if from.is_connected(t[2], cb):
				return ""
			from.connect(t[2], cb, Object.CONNECT_PERSIST)
			return ""
		"group":
			if t.size() < 3:
				return "usage: group Path name"
			var gn := _find(t[1])
			if gn == null:
				return "no node '%s'" % t[1]
			gn.add_to_group(t[2], true)
			return ""
	return "unknown op '%s'" % cmd


## Builds a node from a type name or "@res://scene.tscn". Returns Node or an error String.
func _make(type_or_scene: String) -> Variant:
	if type_or_scene.begins_with("@"):
		var p := C.res_path(type_or_scene.substr(1))
		if p.is_empty() or not ResourceLoader.exists(p):
			return "missing scene " + type_or_scene.substr(1)
		var ps := load(p) as PackedScene
		if ps == null:
			return "not a scene " + p
		return ps.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if not ClassDB.class_exists(type_or_scene):
		# Custom script classes (class_name) are supported too.
		for gc in ProjectSettings.get_global_class_list():
			if gc.class == type_or_scene:
				var inst: Variant = load(gc.path).new()
				if inst is Node:
					return inst
		return "unknown type '%s' (use api tool to look up classes)" % type_or_scene
	if not ClassDB.is_parent_class(type_or_scene, "Node"):
		return "'%s' is not a Node type" % type_or_scene
	if not ClassDB.can_instantiate(type_or_scene):
		return "cannot instantiate " + type_or_scene
	return ClassDB.instantiate(type_or_scene)


func _set_props(node: Node, kvs: Array) -> String:
	var errs: PackedStringArray = []
	# Attach the script first so that its exported variables become settable.
	for kv in kvs:
		if kv[0] == "script":
			var sp := C.res_path(kv[1])
			if sp.is_empty() or not ResourceLoader.exists(sp):
				errs.append("missing script " + kv[1])
			else:
				var s := load(sp) as Script
				if s == null:
					errs.append("not a script " + sp)
				else:
					node.set_script(s)
	for kv in kvs:
		if kv[0] == "script":
			continue
		var e := _set_prop(node, kv[0], kv[1])
		if e != "":
			errs.append(e)
	return "; ".join(errs)


func _set_prop(node: Node, key: String, raw: String) -> String:
	if key == "name":
		node.name = raw
		return ""
	if key == "groups":
		for g in raw.split(","):
			node.add_to_group(g, true)
		return ""
	if key.begins_with("meta/"):
		node.set_meta(key.substr(5), C.parse_value(raw))
		return ""
	# Dotted keys address a property of a sub-resource: shape.size=8,8
	var target: Object = node
	var prop := key
	var dot := key.find(".")
	if dot > 0:
		var head := key.substr(0, dot)
		var sub: Variant = node.get(head)
		if not (sub is Object):
			return "'%s' is not an object" % head
		target = sub
		prop = key.substr(dot + 1)
	var info := C.prop_info(target, prop.get_slice(":", 0))
	if info.is_empty():
		return "%s has no property '%s'" % [target.get_class(), prop]
	if prop.contains(":"):
		# Indexed sub-property such as position:x
		var iv: Variant = C.parse_value(raw)
		target.set_indexed(NodePath(prop), iv)
		return ""
	var res := C.coerce(info, raw)
	if not res[0]:
		return "%s: %s" % [key, res[1]]
	target.set(prop, res[1])
	return ""


## Compact textual outline of a saved scene without instantiating it.
func outline(scene_path: String, with_props: bool = true) -> String:
	var path := C.res_path(scene_path)
	if path.is_empty() or not FileAccess.file_exists(path):
		return "ERR no scene " + scene_path
	var ps := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if ps == null:
		return "ERR cannot load " + path
	var st := ps.get_state()
	var lines: PackedStringArray = []
	for i in st.get_node_count():
		var depth := 0
		var np := String(st.get_node_path(i)).trim_prefix("./")
		if np != "." and np != "":
			depth = np.count("/") + 1
		var line := "  ".repeat(depth) + String(st.get_node_name(i))
		var inst := st.get_node_instance(i)
		if inst != null:
			line += " @" + inst.resource_path
		else:
			line += ":" + String(st.get_node_type(i))
		if with_props:
			for p in st.get_node_property_count(i):
				var pn := String(st.get_node_property_name(i, p))
				line += " %s=%s" % [pn, C.fmt(st.get_node_property_value(i, p))]
		var groups := st.get_node_groups(i)
		if not groups.is_empty():
			line += " groups=" + ",".join(groups)
		lines.append(line)
	var conns: PackedStringArray = []
	for i in st.get_connection_count():
		conns.append("%s.%s -> %s.%s" % [st.get_connection_source(i), st.get_connection_signal(i), st.get_connection_target(i), st.get_connection_method(i)])
	var out := "\n".join(lines)
	if not conns.is_empty():
		out += "\nconn: " + "; ".join(conns)
	return C.trunc(out)
