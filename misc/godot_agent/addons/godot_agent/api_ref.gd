extends RefCounted
## Token-lean class reference built from ClassDB (always matches the running engine build).
##
## Output example:
##   Node2D < CanvasItem < Node < Object
##   P position:Vector2 rotation:float scale:Vector2 ...
##   M apply_scale(ratio:Vector2) get_angle_to(point:Vector2)->float ...
##   V _process(delta) ...
##   S visibility_changed ...
##   K MODE_A MODE_B ...

const C = preload("common.gd")

const MAX_ITEMS := 80


static func _type_name(d: Dictionary) -> String:
	var t: int = d.get("type", TYPE_NIL)
	if t == TYPE_OBJECT:
		var cn := String(d.get("class_name", ""))
		return cn if cn != "" else "Object"
	if t == TYPE_NIL:
		return "Variant"
	return type_string(t)


static func _fit(items: PackedStringArray, limit: int) -> String:
	if items.size() <= limit:
		return " ".join(items)
	return " ".join(items.slice(0, limit)) + " ...+%d (narrow with q=)" % (items.size() - limit)


func lookup(cls: String, q: String = "", own: bool = true, kinds: String = "pmsvk", limit: int = MAX_ITEMS) -> String:
	cls = cls.strip_edges()
	if cls.begins_with("?"):
		return _search(cls.substr(1))
	if not ClassDB.class_exists(cls):
		for gc in ProjectSettings.get_global_class_list():
			if gc.class == cls:
				return "script class %s < %s @ %s (read the file)" % [cls, gc.base, gc.path]
		var hint := _search(cls)
		return "unknown class '%s'. %s" % [cls, hint]
	q = q.to_lower()
	var chain: PackedStringArray = []
	var c := cls
	while c != "":
		chain.append(c)
		c = ClassDB.get_parent_class(c)
	var lines: PackedStringArray = [" < ".join(chain)]
	var scope := [cls] if own else chain
	var props: PackedStringArray = []
	var methods: PackedStringArray = []
	var virtuals: PackedStringArray = []
	var signals_out: PackedStringArray = []
	var consts: PackedStringArray = []
	for sc in scope:
		var prop_names := {}
		for p in ClassDB.class_get_property_list(sc, true):
			prop_names[String(p.name)] = true
		if "p" in kinds:
			for p in ClassDB.class_get_property_list(sc, true):
				if int(p.usage) & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SUBGROUP) or String(p.name).begins_with("_") or not (int(p.usage) & (PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_NO_EDITOR)):
					continue
				if q != "" and not String(p.name).to_lower().contains(q):
					continue
				props.append("%s:%s" % [p.name, _type_name(p)])
		if "m" in kinds or "v" in kinds:
			for m in ClassDB.class_get_method_list(sc, true):
				var mname := String(m.name)
				if q != "" and not mname.to_lower().contains(q):
					continue
				var args: PackedStringArray = []
				for a in m.args:
					args.append("%s:%s" % [a.name, _type_name(a)])
				var sig := "%s(%s)" % [mname, ",".join(args)]
				var rt := _type_name(m.return) if m.has("return") else ""
				if rt != "" and rt != "Variant" and not (m.return.type == TYPE_NIL):
					sig += "->" + rt
				if mname.begins_with("_"):
					if "v" in kinds:
						virtuals.append(sig)
				elif "m" in kinds:
					# Plain accessors are implied by the property list; skip them unless searched.
					var stem := mname.get_slice("_", 0)
					var is_accessor := (stem == "get" or stem == "set" or stem == "is") and prop_names.has(mname.substr(stem.length() + 1))
					if q != "" or not is_accessor:
						methods.append(sig)
		if "s" in kinds:
			for s in ClassDB.class_get_signal_list(sc, true):
				if q != "" and not String(s.name).to_lower().contains(q):
					continue
				var sargs: PackedStringArray = []
				for a in s.args:
					sargs.append("%s:%s" % [a.name, _type_name(a)])
				signals_out.append("%s(%s)" % [s.name, ",".join(sargs)] if not sargs.is_empty() else String(s.name))
		if "k" in kinds:
			for k in ClassDB.class_get_integer_constant_list(sc, true):
				if q != "" and not k.to_lower().contains(q):
					continue
				consts.append(k)
	if not props.is_empty():
		lines.append("P " + _fit(props, limit))
	if not methods.is_empty():
		lines.append("M " + _fit(methods, limit))
	if not virtuals.is_empty():
		lines.append("V " + _fit(virtuals, limit))
	if not signals_out.is_empty():
		lines.append("S " + _fit(signals_out, limit))
	if not consts.is_empty():
		lines.append("K " + _fit(consts, limit))
	if own and lines.size() == 1:
		lines.append("(no own members match; pass own=false for inherited)")
	return C.trunc("\n".join(lines))


func _search(q: String) -> String:
	q = q.to_lower().strip_edges()
	var hits: PackedStringArray = []
	for c in ClassDB.get_class_list():
		if q != "" and String(c).to_lower().contains(q):
			hits.append(c)
	hits.sort()
	if hits.is_empty():
		return "no class matches '%s'" % q
	if hits.size() > 40:
		var more := hits.size() - 40
		hits = hits.slice(0, 40)
		hits.append("...+%d" % more)
	return "classes: " + " ".join(hits)
