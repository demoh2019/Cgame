extends SceneTree
## Cgame API documentation generator.
##
## Scans GDScript files in one directory and writes one Markdown page per script plus a
## top-level index grouped by folder. Extracted per script: the leading `##` header comment,
## top-level `const` / `enum` / `signal` / `class` declarations, documented top-level `var`s and
## every public `func` / `static func` signature (names starting with `_` are skipped) together
## with the `##` comment directly above it. A `##` after a declaration on the same line is used
## when there is no comment above.
##
## CLI (arguments after `--`):
##   godot --headless --path game --script res://scripts/tools/docs_generator.gd -- \
##       --path res://scripts/shared --out /absolute/output/dir
## Pages land in <out>/<folder>/<script>.md and <out>/index.md is rebuilt from every folder
## already present under <out>, so several runs can share one output directory.
##
## Limits: a plain text scan, not a GDScript parser. Doc comments must start in column 0 and
## sit immediately above the declaration; blank lines detach them. Inner-class members and
## multi-line constant bodies are not documented.


## Splits `source` into a Dictionary with the keys header (String), consts, signals, classes,
## vars and funcs (Arrays of Dictionaries with name / decl / doc, funcs also sig / is_static)
## and private_count (int).
static func extract(source: String) -> Dictionary:
	var lines: PackedStringArray = source.replace("\r", "").split("\n")
	var header: String = ""
	var consts: Array = []
	var sig_list: Array = []
	var classes: Array = []
	var vars_doc: Array = []
	var funcs: Array = []
	var private_count: int = 0
	var pending: PackedStringArray = PackedStringArray()
	var header_done: bool = false
	var i: int = 0
	var n: int = lines.size()
	while i < n:
		var line: String = lines[i]
		if line.begins_with("##"):
			pending.append(_strip_doc(line))
			i += 1
			continue
		if line.strip_edges() == "":
			if not pending.is_empty() and not header_done:
				header = "\n".join(pending)
				header_done = true
			pending = PackedStringArray()
			i += 1
			continue
		if line.begins_with("#") or line.begins_with("\t") or line.begins_with(" "):
			i += 1
			continue
		var text: String = line.strip_edges()
		if text.begins_with("extends") or text.begins_with("class_name") or text.begins_with("@tool") or text.begins_with("@icon"):
			if not pending.is_empty() and not header_done:
				header = "\n".join(pending)
				header_done = true
			pending = PackedStringArray()
			i += 1
			continue
		header_done = true
		var doc: String = "\n".join(pending)
		if text.begins_with("const "):
			var parts: Dictionary = _split_trailing_doc(text)
			var cdoc: String = doc if doc != "" else str(parts["doc"])
			consts.append({"name": _decl_name(str(parts["code"]), 6), "decl": _clip(str(parts["code"])), "doc": cdoc})
		elif text.begins_with("enum "):
			var eparts: Dictionary = _split_trailing_doc(text)
			var edoc: String = doc if doc != "" else str(eparts["doc"])
			consts.append({"name": _decl_name(str(eparts["code"]), 5), "decl": _clip(str(eparts["code"])), "doc": edoc})
		elif text.begins_with("signal "):
			var sparts: Dictionary = _split_trailing_doc(text)
			var sdoc: String = doc if doc != "" else str(sparts["doc"])
			sig_list.append({"name": _decl_name(str(sparts["code"]), 7), "decl": _clip(str(sparts["code"])), "doc": sdoc})
		elif text.begins_with("class "):
			var cparts: Dictionary = _split_trailing_doc(text)
			classes.append({"name": _decl_name(str(cparts["code"]), 6), "decl": _clip(str(cparts["code"])), "doc": doc})
		elif text.begins_with("func ") or text.begins_with("static func "):
			var is_static: bool = text.begins_with("static ")
			var read: Dictionary = _read_signature(lines, i)
			var fsig: String = str(read["sig"])
			var fname: String = _decl_name(fsig, 12 if is_static else 5)
			if fname.begins_with("_"):
				private_count += 1
			else:
				funcs.append({"name": fname, "sig": fsig, "doc": doc, "is_static": is_static})
			i = int(read["next"])
			pending = PackedStringArray()
			continue
		elif text.contains("var "):
			var vparts: Dictionary = _split_trailing_doc(text)
			var vdoc: String = doc if doc != "" else str(vparts["doc"])
			var vcode: String = str(vparts["code"])
			var vpos: int = vcode.find("var ")
			if vdoc != "" and vpos >= 0:
				vars_doc.append({"name": _decl_name(vcode, vpos + 4), "decl": _clip(vcode), "doc": vdoc})
		pending = PackedStringArray()
		i += 1
	return {
		"header": header, "consts": consts, "signals": sig_list, "classes": classes,
		"vars": vars_doc, "funcs": funcs, "private_count": private_count,
	}


static func _strip_doc(line: String) -> String:
	var s: String = line.substr(2)
	if s.begins_with(" "):
		s = s.substr(1)
	return s.rstrip(" \t")


static func _clip(text: String) -> String:
	if text.length() > 160:
		return text.substr(0, 157) + "..."
	return text


static func _decl_name(text: String, prefix_len: int) -> String:
	var rest: String = text.substr(prefix_len)
	var end: int = rest.length()
	for stop: String in PackedStringArray([":", "=", " ", "("]):
		var p: int = rest.find(stop)
		if p >= 0 and p < end:
			end = p
	return rest.substr(0, end)


static func _split_trailing_doc(text: String) -> Dictionary:
	var p: int = text.find(" ## ")
	if p <= 0:
		return {"code": text, "doc": ""}
	return {"code": text.substr(0, p).strip_edges(), "doc": text.substr(p + 4).strip_edges()}


## Reads a possibly multi-line function signature starting at lines[start]; stops at the first
## ':' outside brackets and strings. Returns {sig: String, next: int (index after the header)}.
static func _read_signature(lines: PackedStringArray, start: int) -> Dictionary:
	var sig: String = ""
	var depth: int = 0
	var opened: bool = false
	var quote: String = ""
	var done: bool = false
	var i: int = start
	while i < lines.size() and not done and i - start < 40:
		var text: String = lines[i].strip_edges()
		if i > start:
			sig += " "
		var j: int = 0
		while j < text.length():
			var ch: String = text[j]
			if quote != "":
				sig += ch
				if ch == "\\" and j + 1 < text.length():
					sig += text[j + 1]
					j += 1
				elif ch == quote:
					quote = ""
			elif ch == "\"" or ch == "'":
				quote = ch
				sig += ch
			elif ch == "#":
				break
			elif ch == "(" or ch == "[" or ch == "{":
				depth += 1
				opened = opened or ch == "("
				sig += ch
			elif ch == ")" or ch == "]" or ch == "}":
				depth -= 1
				sig += ch
			elif ch == ":" and depth == 0 and opened:
				done = true
				break
			else:
				sig += ch
			j += 1
		i += 1
	sig = sig.replace("( ", "(").replace(" )", ")").replace(", )", ")").replace("  ", " ")
	return {"sig": sig.strip_edges(), "next": i}


## First sentence of the header comment (at most ~160 characters), used by the index pages.
static func summary_of(header: String) -> String:
	if header.strip_edges() == "":
		return "(no header comment)"
	var words: PackedStringArray = PackedStringArray()
	for raw: String in header.split("\n"):
		var piece: String = raw.strip_edges()
		if piece == "":
			break
		words.append(piece)
	var flat: String = " ".join(words)
	var cut: int = flat.find(". ")
	if cut > 0:
		flat = flat.substr(0, cut + 1)
	if flat.length() > 160:
		flat = flat.substr(0, 157) + "..."
	return flat


## Doc text as Markdown. Text with indented lines (asset layouts, ASCII tables) is fenced so the
## layout survives; plain prose is emitted as is.
static func doc_block(doc: String) -> String:
	if doc.strip_edges() == "":
		return ""
	var fenced: bool = false
	for raw: String in doc.split("\n"):
		if raw.begins_with(" ") or raw.begins_with("\t"):
			fenced = true
			break
	if fenced:
		return "```text\n%s\n```\n" % doc
	return doc + "\n"


## Renders the Markdown page for one script. `res_path` is shown verbatim under the title.
static func render_page(script_name: String, res_path: String, info: Dictionary) -> String:
	var header: String = str(info["header"])
	var out: String = "# %s\n\n> %s\n\n`%s`\n\n" % [script_name, summary_of(header), res_path]
	if header.strip_edges() != "":
		out += "## Overview\n\n" + doc_block(header) + "\n"
	out += _render_decl_section("Constants", info["consts"])
	out += _render_decl_section("Signals", info["signals"])
	out += _render_decl_section("Classes", info["classes"])
	out += _render_decl_section("Documented variables", info["vars"])
	var funcs: Array = info["funcs"]
	if not funcs.is_empty():
		out += "## Functions\n\n"
		for item: Dictionary in funcs:
			out += "### `%s`\n\n" % str(item["name"])
			out += "```gdscript\n%s\n```\n\n" % str(item["sig"])
			var fdoc: String = doc_block(str(item["doc"]))
			if fdoc != "":
				out += fdoc + "\n"
	var hidden: int = int(info["private_count"])
	if hidden > 0:
		out += "_%d private function(s) starting with `_` are not listed._\n" % hidden
	return out


static func _render_decl_section(title: String, items: Array) -> String:
	if items.is_empty():
		return ""
	var out: String = "## %s\n\n" % title
	for item: Dictionary in items:
		var line: String = "- `%s`" % str(item["decl"])
		var doc: String = str(item["doc"]).replace("\n", " ").strip_edges()
		if doc != "":
			line += " - " + doc
		out += line + "\n"
	return out + "\n"


## Writes one page per .gd file directly inside `res_dir` into <out_dir>/<folder>/. Returns the
## number of pages written, or -1 when the directory cannot be read.
static func generate(res_dir: String, out_dir: String) -> int:
	var dir: DirAccess = DirAccess.open(res_dir)
	if dir == null:
		return -1
	var folder: String = res_dir.trim_suffix("/").get_file()
	var target: String = out_dir.path_join(folder)
	DirAccess.make_dir_recursive_absolute(target)
	var names: PackedStringArray = PackedStringArray()
	for file_name: String in dir.get_files():
		if file_name.ends_with(".gd"):
			names.append(file_name)
	names.sort()
	var count: int = 0
	for file_name: String in names:
		var res_path: String = res_dir.trim_suffix("/") + "/" + file_name
		var source: String = FileAccess.get_file_as_string(res_path)
		var page: String = render_page(file_name, res_path, extract(source))
		var file: FileAccess = FileAccess.open(target.path_join(file_name.trim_suffix(".gd") + ".md"), FileAccess.WRITE)
		if file == null:
			return -1
		file.store_string(page)
		file.close()
		count += 1
	return count


## Rebuilds <out_dir>/index.md from every sub-folder of `out_dir` that holds generated pages.
## Returns the number of pages listed.
static func build_index(out_dir: String) -> int:
	var root: DirAccess = DirAccess.open(out_dir)
	if root == null:
		return 0
	var folders: PackedStringArray = root.get_directories()
	folders.sort()
	var total: int = 0
	var body: String = ""
	for folder: String in folders:
		var sub: DirAccess = DirAccess.open(out_dir.path_join(folder))
		if sub == null:
			continue
		var pages: PackedStringArray = PackedStringArray()
		for file_name: String in sub.get_files():
			if file_name.ends_with(".md"):
				pages.append(file_name)
		if pages.is_empty():
			continue
		pages.sort()
		body += "## %s (%d scripts)\n\n" % [folder, pages.size()]
		for page_name: String in pages:
			var first: PackedStringArray = FileAccess.get_file_as_string(out_dir.path_join(folder).path_join(page_name)).split("\n")
			var summary: String = ""
			if first.size() > 2 and first[2].begins_with("> "):
				summary = first[2].substr(2)
			body += "- [`%s.gd`](%s/%s) - %s\n" % [page_name.trim_suffix(".md"), folder, page_name, summary]
			total += 1
		body += "\n"
	var text: String = "# Cgame API reference\n\nGenerated by `game/scripts/tools/docs_generator.gd` from the `##` doc comments "
	text += "in the GDScript sources. %d script pages. Do not edit by hand; regenerate instead.\n\n" % total
	text += body
	var file: FileAccess = FileAccess.open(out_dir.path_join("index.md"), FileAccess.WRITE)
	if file == null:
		return 0
	file.store_string(text)
	file.close()
	return total


static func parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"path": "", "out": ""}
	var i: int = 0
	while i < args.size():
		if args[i] == "--path" and i + 1 < args.size():
			result["path"] = args[i + 1]
			i += 1
		elif args[i] == "--out" and i + 1 < args.size():
			result["out"] = args[i + 1]
			i += 1
		i += 1
	return result


func _initialize() -> void:
	var args: Dictionary = parse_args(OS.get_cmdline_user_args())
	var res_dir: String = str(args["path"])
	var out_dir: String = str(args["out"])
	if res_dir == "" or out_dir == "":
		printerr("usage: -- --path <res://dir> --out <absolute output dir>")
		quit(2)
		return
	var written: int = generate(res_dir, out_dir)
	if written < 0:
		printerr("docs_generator: cannot read %s or write under %s" % [res_dir, out_dir])
		quit(1)
		return
	var listed: int = build_index(out_dir)
	print("docs_generator: %d pages for %s, index lists %d" % [written, res_dir, listed])
	quit(0)
