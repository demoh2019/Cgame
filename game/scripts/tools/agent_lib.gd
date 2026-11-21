extends RefCounted
## Shared, headless-safe helpers for AI-agent tooling.
##
## Used by `agent_cli.gd` (command line, JSON output) and by the editor addon
## `res://addons/cgame_mcp/`. Everything returns plain Dictionaries/Arrays so the callers can
## `JSON.stringify` the result directly. No editor APIs are used here.

const SKIP_DIRS: Array[String] = [".godot", "assets", "com.heroiclabs.nakama", "node_modules", ".git"]


## One captured engine error (parse/analyzer errors are reported through the Logger interface).
class ErrorCapture extends Logger:
	var items: Array[Dictionary] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var text: String = rationale if not rationale.is_empty() else code
		items.append({
			"file": file,
			"line": line,
			"message": text,
			"function": function,
			"kind": "warning" if error_type == Logger.ERROR_TYPE_WARNING else "error",
		})


## Absolute path of the game project directory (no trailing slash).
static func project_dir() -> String:
	return ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")


## Absolute path of the repository root (parent of `game/`) when the project lives in it.
static func repo_dir() -> String:
	var parent: String = project_dir().get_base_dir()
	if DirAccess.dir_exists_absolute(parent.path_join("modules")):
		return parent
	return project_dir()


static func to_res(path: String) -> String:
	if path.begins_with("res://"):
		return path
	var root: String = project_dir() + "/"
	if path.begins_with(root):
		return "res://" + path.substr(root.length())
	return "res://" + path.trim_prefix("./")


## Recursively lists files below `dir` (res:// or absolute) with one of `exts` (e.g. [".gd"]).
static func list_files(dir: String, exts: Array[String], out: Array[String], skip_assets: bool = true) -> void:
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = false
	var subdirs: Array[String] = []
	for f: String in da.get_files():
		for e in exts:
			if f.ends_with(e):
				out.append(dir.path_join(f))
				break
	for d: String in da.get_directories():
		if skip_assets and SKIP_DIRS.has(d):
			continue
		subdirs.append(d)
	subdirs.sort()
	for d in subdirs:
		list_files(dir.path_join(d), exts, out, skip_assets)


## Parse-checks one GDScript from its on-disk source. Returns {path, ok, errors:[{line,message,kind}]}.
## Warnings are errors in this project, so the analyzer reports them as errors as well.
static func check_script(path: String) -> Dictionary:
	var res_path: String = to_res(path)
	var result: Dictionary = {"path": res_path, "ok": true, "errors": []}
	if not FileAccess.file_exists(res_path):
		result["ok"] = false
		result["errors"] = [{"line": 0, "message": "file not found", "kind": "error"}]
		return result
	var cap: ErrorCapture = ErrorCapture.new()
	OS.add_logger(cap)
	var script: GDScript = GDScript.new()
	script.source_code = FileAccess.get_file_as_string(res_path)
	var err: int = script.reload()
	OS.remove_logger(cap)
	var errors: Array = result["errors"]
	var seen_lines: Dictionary = {}
	for item: Dictionary in cap.items:
		if seen_lines.has(item["line"]) and item["kind"] == "error":
			continue
		seen_lines[item["line"]] = true
		errors.append({"line": item["line"], "message": str(item["message"]).left(300), "kind": item["kind"]})
	if err != OK and errors.is_empty():
		errors.append({"line": 0, "message": "reload failed: %s" % error_string(err), "kind": "error"})
	result["ok"] = err == OK and errors.is_empty()
	return result


## Expands "all" / directories / files into a sorted list of res:// .gd paths.
static func expand_script_paths(inputs: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in inputs:
		var p: String = str(raw)
		if p == "all":
			for d in ["res://scripts", "res://tests", "res://addons"]:
				list_files(d, [".gd"], out)
			continue
		var rp: String = to_res(p)
		if DirAccess.dir_exists_absolute(rp):
			list_files(rp, [".gd"], out)
		elif rp.ends_with(".gd"):
			out.append(rp)
	return out


## Checks many scripts; returns compact {checked, failed, errors:[{path,line,message}]}.
static func check_scripts(inputs: Array, max_errors: int = 100) -> Dictionary:
	var paths: Array[String] = expand_script_paths(inputs)
	var failed_files: int = 0
	var errors: Array[Dictionary] = []
	for p in paths:
		var r: Dictionary = check_script(p)
		if not bool(r["ok"]):
			failed_files += 1
			for e: Dictionary in r["errors"]:
				if errors.size() < max_errors:
					errors.append({"path": p, "line": e["line"], "message": e["message"]})
	return {"checked": paths.size(), "failed": failed_files, "errors": errors,
		"truncated": failed_files > 0 and errors.size() >= max_errors}


## Test suites in res://tests (`test_*.gd`) with the number of assertion call sites per file.
static func list_suites() -> Array[Dictionary]:
	var files: Array[String] = []
	list_files("res://tests", [".gd"], files)
	var rx: RegEx = RegEx.new()
	rx.compile("\\bt\\.(check|eq|near)\\(")
	var out: Array[Dictionary] = []
	for f in files:
		var base: String = f.get_file()
		if not base.begins_with("test_"):
			continue
		var src: String = FileAccess.get_file_as_string(f)
		out.append({"name": base.trim_suffix(".gd"), "checks": rx.search_all(src).size()})
	return out


## Runs run_one.gd / run_all.gd in a child process (blocking) and returns a compact summary.
static func run_tests(suites: Array, timeout_note: bool = false) -> Dictionary:
	var args: PackedStringArray = ["--headless", "--path", project_dir()]
	var names: Array[String] = []
	for s in suites:
		names.append(str(s))
	if names.is_empty() or names.has("all"):
		args.append_array(["--script", "res://tests/run_all.gd"])
	else:
		args.append_array(["--script", "res://tests/run_one.gd", "--"])
		args.append_array(PackedStringArray(names))
	var output: Array = []
	var started: int = Time.get_ticks_msec()
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var summary: Dictionary = parse_test_output(output[0] if output.size() > 0 else "")
	summary["exit_code"] = code
	summary["seconds"] = snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1)
	summary["ok"] = code == 0 and int(summary.get("failures", 1)) == 0
	if timeout_note:
		summary["note"] = "blocking run"
	return summary


## Parses `NAME  N checks  M failed`, `FAIL ...` and `TOTAL N checks, M failures` lines.
static func parse_test_output(text: String) -> Dictionary:
	var suites: Array[Dictionary] = []
	var fails: Array[String] = []
	var total_checks: int = -1
	var total_failures: int = -1
	var script_errors: Array[String] = []
	var rx_suite: RegEx = RegEx.new()
	rx_suite.compile("^(\\S+\\.gd)\\s+(\\d+) checks\\s+(\\d+) failed")
	var rx_total: RegEx = RegEx.new()
	rx_total.compile("TOTAL (\\d+) checks, (\\d+) failures")
	for line in text.split("\n"):
		var l: String = line.strip_edges(false, true)
		if l.begins_with("FAIL "):
			if fails.size() < 60:
				fails.append(l.substr(5).left(300))
			continue
		var m: RegExMatch = rx_total.search(l)
		if m != null:
			total_checks = int(m.get_string(1))
			total_failures = int(m.get_string(2))
			continue
		m = rx_suite.search(l)
		if m != null:
			if int(m.get_string(3)) > 0:
				suites.append({"suite": m.get_string(1), "checks": int(m.get_string(2)), "failed": int(m.get_string(3))})
			continue
		if (l.begins_with("SCRIPT ERROR") or l.begins_with("ERROR:") or l.begins_with("Parse Error")) and script_errors.size() < 20:
			script_errors.append(l.left(300))
	return {"checks": total_checks, "failures": total_failures if total_failures >= 0 else 1,
		"failing_suites": suites, "fail_lines": fails, "script_errors": script_errors,
		"complete": total_checks >= 0}


## ClassDB class names containing `filter` (case-insensitive), with parent. Limited.
static func classes(filter: String, limit: int = 60) -> Dictionary:
	var f: String = filter.to_lower()
	var out: Array[String] = []
	var total: int = 0
	var names: PackedStringArray = ClassDB.get_class_list()
	var sorted_names: Array = Array(names)
	sorted_names.sort()
	for n: String in sorted_names:
		if f.is_empty() or n.to_lower().contains(f):
			total += 1
			if out.size() < limit:
				var parent: String = ClassDB.get_parent_class(n)
				out.append(n if parent.is_empty() else "%s<%s" % [n, parent])
	return {"filter": filter, "total": total, "shown": out.size(), "classes": out}


## ClassDB reflection for one class, or the public API of a GDScript library when no class matches.
static func api(name: String, member_filter: String = "", limit: int = 80) -> Dictionary:
	if ClassDB.class_exists(name):
		return _class_api(name, member_filter, limit)
	var path: String = _find_script(name)
	if path.is_empty():
		return {"error": "no ClassDB class or script named '%s'" % name}
	return _script_api(path, member_filter, limit)


static func _class_api(name: String, member_filter: String, limit: int) -> Dictionary:
	var f: String = member_filter.to_lower()
	var methods: Array[String] = []
	for m: Dictionary in ClassDB.class_get_method_list(name, true):
		var mn: String = str(m["name"])
		if mn.begins_with("_") and not _has_flag(int(m["flags"]), METHOD_FLAG_VIRTUAL):
			continue
		if not f.is_empty() and not mn.to_lower().contains(f):
			continue
		var args: Array[String] = []
		for a: Dictionary in m["args"]:
			args.append("%s: %s" % [a["name"], _type_name(a)])
		var ret: String = _type_name(m["return"]) if m.has("return") else "void"
		var static_prefix: String = "static " if _has_flag(int(m["flags"]), METHOD_FLAG_STATIC) else ""
		methods.append("%s%s(%s) -> %s" % [static_prefix, mn, ", ".join(args), ret])
	var props: Array[String] = []
	for p: Dictionary in ClassDB.class_get_property_list(name, true):
		var pn: String = str(p["name"])
		if not _has_flag(int(p["usage"]), PROPERTY_USAGE_EDITOR):
			continue
		if not f.is_empty() and not pn.to_lower().contains(f):
			continue
		props.append("%s: %s" % [pn, _type_name(p)])
	var sigs: Array[String] = []
	for s: Dictionary in ClassDB.class_get_signal_list(name, true):
		var sn: String = str(s["name"])
		if f.is_empty() or sn.to_lower().contains(f):
			var sargs: Array[String] = []
			for a: Dictionary in s["args"]:
				sargs.append("%s: %s" % [a["name"], _type_name(a)])
			sigs.append("%s(%s)" % [sn, ", ".join(sargs)])
	var consts: Array[String] = []
	for c in ClassDB.class_get_integer_constant_list(name, true):
		if f.is_empty() or str(c).to_lower().contains(f):
			consts.append(str(c))
	return {"class": name, "parent": ClassDB.get_parent_class(name),
		"methods": methods.slice(0, limit), "methods_total": methods.size(),
		"properties": props.slice(0, limit), "properties_total": props.size(),
		"signals": sigs.slice(0, limit), "constants": consts.slice(0, limit),
		"can_instantiate": ClassDB.can_instantiate(name)}


static func _has_flag(flags: int, mask: int) -> bool:
	return (flags & mask) != 0


static func _type_name(d: Dictionary) -> String:
	var cn: String = str(d.get("class_name", ""))
	if not cn.is_empty():
		return cn
	var t: int = int(d.get("type", 0))
	return "Variant" if t == TYPE_NIL else type_string(t)


## Finds res://scripts/**/<name>.gd (name with or without extension / folder prefix).
static func _find_script(name: String) -> String:
	if name.begins_with("res://") and FileAccess.file_exists(name):
		return name
	var want: String = name.trim_suffix(".gd").to_lower()
	var files: Array[String] = []
	list_files("res://scripts", [".gd"], files)
	var best: String = ""
	for f in files:
		var rel: String = f.trim_prefix("res://scripts/").trim_suffix(".gd").to_lower()
		if rel == want or f.get_file().trim_suffix(".gd").to_lower() == want:
			return f
		if best.is_empty() and rel.contains(want):
			best = f
	return best


static func _script_api(path: String, member_filter: String, limit: int) -> Dictionary:
	var f: String = member_filter.to_lower()
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	var header: String = ""
	var funcs: Array[String] = []
	var consts: Array[String] = []
	var signals_out: Array[String] = []
	var vars: Array[String] = []
	var i: int = 0
	while i < lines.size() and lines[i].begins_with("##") and header.length() < 400:
		header += lines[i].trim_prefix("##").strip_edges() + " "
		i += 1
	var doc: String = ""
	for idx in range(lines.size()):
		var l: String = lines[idx]
		if l.begins_with("##"):
			doc = l.trim_prefix("##").strip_edges()
			continue
		var is_static: bool = l.begins_with("static func ")
		if l.begins_with("func ") or is_static:
			var full_line: String = l
			var k: int = idx
			while not full_line.strip_edges().ends_with(":") and k + 1 < lines.size() and k - idx < 8:
				k += 1
				full_line += " " + lines[k].strip_edges()
			var sig: String = full_line.trim_prefix("static ").trim_prefix("func ").strip_edges().trim_suffix(":").strip_edges()
			if sig.contains(" -> "):
				sig = sig.left(sig.find(":", sig.find(" -> ")) if sig.find(":", sig.find(" -> ")) > 0 else sig.length())
			if sig.begins_with("_") or (not f.is_empty() and not sig.to_lower().contains(f)):
				doc = ""
				continue
			var entry: String = ("static " if is_static else "") + sig
			if not doc.is_empty():
				entry += "  # " + doc.left(100)
			funcs.append(entry)
		elif l.begins_with("const ") or l.begins_with("signal ") or l.begins_with("enum "):
			var sig2: String = l.strip_edges().left(110)
			if not f.is_empty() and not sig2.to_lower().contains(f):
				doc = ""
				continue
			if l.begins_with("signal "):
				signals_out.append(sig2)
			elif not l.contains("preload("):
				consts.append(sig2)
		elif l.begins_with("var ") or l.begins_with("static var "):
			var sig3: String = l.strip_edges().left(90)
			if not sig3.contains(" _") and (f.is_empty() or sig3.to_lower().contains(f)):
				vars.append(sig3)
		doc = ""
	return {"script": path, "summary": header.strip_edges().left(400),
		"functions": funcs.slice(0, limit), "functions_total": funcs.size(),
		"constants": consts.slice(0, 30), "signals": signals_out.slice(0, 20), "vars": vars.slice(0, 30)}


## Text search for where `symbol` is defined: GDScript defs under scripts/tests/addons and C++ in modules/cgame_*.
static func find_symbol(symbol: String, limit: int = 40) -> Dictionary:
	var hits: Array[Dictionary] = []
	var sym: String = symbol.strip_edges()
	if sym.is_empty():
		return {"error": "empty symbol"}
	var esc: String = _regex_escape(sym)
	var rx_gd: RegEx = RegEx.new()
	rx_gd.compile("^\\s*(?:static\\s+)?(?:func|const|signal|enum|var|class)\\s+" + esc + "\\b")
	var rx_cpp: RegEx = RegEx.new()
	rx_cpp.compile("(?:\\b(?:class|struct|enum)\\s+" + esc + "\\b|::" + esc + "\\s*\\(|D_METHOD\\(\"" + esc + "\"|GDREGISTER_\\w*CLASS\\(" + esc + "\\)|ADD_SIGNAL\\(MethodInfo\\(\"" + esc + "\")")
	var gd_files: Array[String] = []
	for d in ["res://scripts", "res://addons", "res://tests"]:
		list_files(d, [".gd"], gd_files)
	for p in gd_files:
		_scan_file(p, rx_gd, hits, limit, p)
		if hits.size() >= limit:
			break
	if hits.size() < limit:
		var cpp_files: Array[String] = []
		var modules: String = repo_dir().path_join("modules")
		var da: DirAccess = DirAccess.open(modules)
		if da != null:
			var dirs: Array = Array(da.get_directories())
			dirs.sort()
			for d: String in dirs:
				if d.begins_with("cgame_"):
					list_files(modules.path_join(d), [".cpp", ".h"], cpp_files, false)
		for p in cpp_files:
			_scan_file(p, rx_cpp, hits, limit, "modules/" + p.trim_prefix(modules + "/"))
			if hits.size() >= limit:
				break
	return {"symbol": sym, "count": hits.size(), "hits": hits, "truncated": hits.size() >= limit}


static func _scan_file(path: String, rx: RegEx, hits: Array[Dictionary], limit: int, label: String) -> void:
	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	for n in range(lines.size()):
		if rx.search(lines[n]) != null:
			hits.append({"file": label, "line": n + 1, "text": lines[n].strip_edges().left(140)})
			if hits.size() >= limit:
				return


static func _regex_escape(s: String) -> String:
	var out: String = ""
	for ch in s:
		if "\\.^$|?*+()[]{}".contains(ch):
			out += "\\"
		out += ch
	return out


## grep-like search over res:// text files. `glob_ext` like ".gd" (empty = gd, md, tscn, tres, cfg, json, gdshader).
static func search_project(pattern: String, ext: String = "", limit: int = 40, regex: bool = false,
		subdir: String = "res://") -> Dictionary:
	var exts: Array[String] = [ext] if not ext.is_empty() else [".gd", ".md", ".tscn", ".tres", ".cfg", ".json", ".gdshader"]
	var files: Array[String] = []
	list_files(subdir, exts, files)
	var rx: RegEx = null
	if regex:
		rx = RegEx.new()
		if rx.compile(pattern) != OK:
			return {"error": "invalid regex"}
	var needle: String = pattern.to_lower()
	var hits: Array[Dictionary] = []
	var scanned: int = 0
	for p in files:
		scanned += 1
		var lines: PackedStringArray = FileAccess.get_file_as_string(p).split("\n")
		for n in range(lines.size()):
			var found: bool = rx.search(lines[n]) != null if regex else lines[n].to_lower().contains(needle)
			if found:
				hits.append({"file": p, "line": n + 1, "text": lines[n].strip_edges().left(140)})
				if hits.size() >= limit:
					return {"pattern": pattern, "scanned_files": scanned, "count": hits.size(), "hits": hits, "truncated": true}
	return {"pattern": pattern, "scanned_files": scanned, "count": hits.size(), "hits": hits, "truncated": false}


## Compact project map for orientation (folders, entry scripts, addons, modules, tests).
static func project_map(full: bool = false) -> Dictionary:
	var folders: Dictionary = {}
	for sub in ["shared", "client", "server", "tools", "native"]:
		var fl: Array[String] = []
		list_files("res://scripts/" + sub, [".gd"], fl)
		folders["scripts/" + sub] = fl.size()
	var addons: Array[String] = []
	var da: DirAccess = DirAccess.open("res://addons")
	if da != null:
		var dirs: Array = Array(da.get_directories())
		dirs.sort()
		for d: String in dirs:
			var cfg: ConfigFile = ConfigFile.new()
			if cfg.load("res://addons/%s/plugin.cfg" % d) == OK:
				addons.append("%s: %s" % [d, str(cfg.get_value("plugin", "name", d))])
	var modules: Array[String] = []
	var mroot: String = repo_dir().path_join("modules")
	var md: DirAccess = DirAccess.open(mroot)
	if md != null:
		var mdirs: Array = Array(md.get_directories())
		mdirs.sort()
		for d: String in mdirs:
			if d.begins_with("cgame_"):
				modules.append(d)
	var suites: Array[Dictionary] = list_suites()
	var total_checks: int = 0
	for s in suites:
		total_checks += int(s["checks"])
	suites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["checks"]) > int(b["checks"]))
	var docs: Array[String] = []
	list_files("res://docs", [".md"], docs)
	var runners: Array[String] = []
	var tests_dir: DirAccess = DirAccess.open("res://tests")
	if tests_dir != null:
		for f in tests_dir.get_files():
			if f.begins_with("run_") and f.ends_with(".gd"):
				runners.append(f)
	var result: Dictionary = {
		"project": str(ProjectSettings.get_setting("application/config/name", "")),
		"main_scene": str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"engine": str(Engine.get_version_info().get("string", "")),
		"script_folders": folders,
		"entry": ["res://tests/run_all.gd", "res://tests/run_one.gd", "res://scripts/tools/agent_cli.gd"],
		"addons": addons,
		"modules": modules,
		"game_docs_count": docs.size(),
		"test_suites": {"count": suites.size(), "assertion_sites": total_checks,
			"runners": runners.size()},
	}
	var top: Array[String] = []
	for s in suites.slice(0, suites.size() if full else 10):
		top.append("%s:%d" % [s["name"], s["checks"]])
	result["test_suites"]["largest" if not full else "all"] = top
	return result


## Which cgame_* native classes exist in this binary, and which script facades reference them.
static func native_status() -> Dictionary:
	var rx_reg: RegEx = RegEx.new()
	rx_reg.compile("GDREGISTER_\\w*CLASS\\((\\w+)\\)")
	var modules: Dictionary = {}
	var mroot: String = repo_dir().path_join("modules")
	var md: DirAccess = DirAccess.open(mroot)
	if md != null:
		var mdirs: Array = Array(md.get_directories())
		mdirs.sort()
		for d: String in mdirs:
			if not d.begins_with("cgame_"):
				continue
			var src: String = FileAccess.get_file_as_string(mroot.path_join(d).path_join("register_types.cpp"))
			var present: Array[String] = []
			var missing: Array[String] = []
			for m in rx_reg.search_all(src):
				var cn: String = m.get_string(1)
				if ClassDB.class_exists(cn):
					present.append(cn)
				else:
					missing.append(cn)
			modules[d] = {"present": present.size(), "missing": missing}
	var rx_use: RegEx = RegEx.new()
	rx_use.compile("(?:class_exists|available|singleton)\\(\\s*&?\"(\\w+)\"")
	var facades: Dictionary = {}
	var nf: Array[String] = []
	list_files("res://scripts/native", [".gd"], nf)
	for p in nf:
		var found: Dictionary = {}
		for m in rx_use.search_all(FileAccess.get_file_as_string(p)):
			found[m.get_string(1)] = ClassDB.class_exists(m.get_string(1))
		if not found.is_empty():
			var fallback: Array[String] = []
			for k: String in found:
				if not bool(found[k]):
					fallback.append(k)
			facades[p.get_file().trim_suffix(".gd")] = {"native": found.size() - fallback.size(), "fallback_for": fallback}
	return {"engine": str(Engine.get_version_info().get("string", "")), "modules": modules, "facades": facades}
