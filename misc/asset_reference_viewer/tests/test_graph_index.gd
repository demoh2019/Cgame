extends SceneTree

const Graph = preload("res://addons/asset_reference_viewer/graph_index.gd")
const ROOT = "user://cgame_asset_reference_viewer_test"

var passed := 0
var failed := 0


func _initialize() -> void:
	_test_parser()
	_test_graph()
	_test_traversal()
	_test_disk()
	print("Asset Reference Viewer: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAILED: " + label)


func _sample() -> Dictionary:
	return {
		"scenes/main.tscn": 'path="res://scenes/player.tscn"\npath="res://art/icon.png"',
		"scenes/player.tscn": 'path="res://scripts/player.gd"',
		"scripts/player.gd": 'var sprite = preload("res://art/icon.png")',
		"art/icon.png": null,
		"README.txt": "This is not a resource file",
		"unused.tres": "[gd_resource format=3]",
	}


func _test_parser() -> void:
	var script_refs = Graph.extract_references('var image = load("res://art/icon.png")', "gd")
	_check("one quoted GDScript literal", script_refs.size() == 1)
	_check("resource path without scheme", script_refs[0]["target"] == "art/icon.png")
	_check("first line numbering", script_refs[0]["line"] == 1)
	_check("GDScript single quoted", Graph.extract_references("load('res://art/icon.png')", "gd").size() == 1)
	_check("ignore full GDScript comment", Graph.extract_references('# load("res://missing.tres")', "gd").is_empty())
	_check("ignore GDScript inline comment", Graph.extract_references('var x = 1 # load("res://missing.tres")', "gd").is_empty())
	_check("ignore C# inline comment", Graph.extract_references('int x = 1; // GD.Load("res://missing.tres")', "cs").is_empty())
	_check("ignore shader inline comment", Graph.extract_references('void fragment() {} // "res://missing.tres"', "gdshader").is_empty())
	_check("shader include is a reference", Graph.extract_references('#include "res://shaders/common.gdshaderinc"', "gdshader").size() == 1)
	_check("hash inside literal is allowed", Graph.extract_references('load("res://assets/#icon.tres")', "gd").size() == 1)
	_check("URL inside literal not comment", Graph.extract_references('var url = "https://host"; load("res://a.tres")', "cs").size() == 1)
	_check("double slash inside literal not comment", Graph.extract_references('load("res://assets//alias.png")', "gd").size() == 1)
	_check("trailing prose not a reference", Graph.extract_references('var t = "Open res://a.tres later"', "gd").is_empty())
	_check("unquoted paths ignored", Graph.extract_references('var t = res://a.tres', "gd").is_empty())
	_check("incomplete quoted literal ignored", Graph.extract_references('load("res://broken', "gd").is_empty())
	_check("non-resource URI ignored", Graph.extract_references('load("user://score.tres")', "gd").is_empty())
	_check("uid URI ignored", Graph.extract_references('load("uid://abcdef")', "gd").is_empty())
	_check("empty resource target captured", Graph.extract_references('load("res://")', "gd")[0]["target"] == "")
	_check("escaped quote does not terminate string", Graph.extract_references('var a = "escaped \\" quote"; load("res://a.tres")', "gd").size() == 1)
	_check("multiple occurrences preserved", Graph.extract_references('load("res://a.tres"); load("res://a.tres")', "gd").size() == 2)
	var multiline = Graph.extract_references('var a = 1\nload("res://a.tres")\n# load("res://ignored")', "gd")
	_check("line numbers after newline", multiline.size() == 1 and multiline[0]["line"] == 2)
	_check("comment marker in string", Graph.extract_references('var a = "#"; load("res://ok.tres")', "gd").size() == 1)
	_check("shader include trailing comment", Graph.extract_references('#include "res://a.gdshaderinc" // "res://bad"', "gdshader").size() == 1)
	_check("full C# line comment", Graph.extract_references('// GD.Load("res://missing.tres")', "cs").is_empty())


func _test_graph() -> void:
	var graph = Graph.build_from_files(_sample())
	_check("six assets indexed", graph["nodes"].size() == 6)
	_check("four edges indexed", graph["references"].size() == 4)
	_check("nodes are sorted", graph["nodes"][0] == "README.txt")
	_check("binary asset is selectable", graph["nodes"].has("art/icon.png"))
	_check("graph has no errors", graph["errors"].is_empty())
	_check("source path is relative", graph["references"][0]["source"] == "scenes/main.tscn")
	_check("line one preserved", graph["references"][0]["line"] == 1)
	_check("line two preserved", graph["references"][1]["line"] == 2)
	_check("build deterministic", graph == Graph.build_from_files(_sample()))
	_check("input untouched", _sample()["art/icon.png"] == null)
	var missing = Graph.build_from_files({"main.gd": 'load("res://not_found.tres")'})
	_check("missing resource cannot create edge", missing["references"].is_empty())
	var mismatch = Graph.build_from_files({"main.gd": 'load("res://art/Icon.png")', "art/icon.png": null})
	_check("case mismatch cannot create edge", mismatch["references"].is_empty())
	var traversal = Graph.build_from_files({"main.gd": 'load("res://../file.tres")', "file.tres": ""})
	_check("path traversal does not resolve", traversal["references"].is_empty())
	var slash = Graph.build_from_files({"main.gd": "load('res://art\\\\a.tres')", "art/a.tres": ""})
	_check("backslash does not resolve", slash["references"].is_empty())
	var selfref = Graph.build_from_files({"self.gd": 'load("res://self.gd")'})
	_check("self references retained", selfref["references"].size() == 1)
	var duplicate = Graph.build_from_files({"scene.tscn": 'path="res://a.tres"\npath="res://a.tres"', "a.tres": ""})
	_check("duplicate references retained with lines", duplicate["references"].size() == 2 and duplicate["references"][1]["line"] == 2)
	var unsupported = Graph.build_from_files({"notes.txt": 'load("res://a.tres")', "a.tres": ""})
	_check("text extension filter", unsupported["references"].is_empty())
	var empty = Graph.build_from_files({})
	_check("empty graph valid", empty["nodes"].is_empty() and empty["references"].is_empty())


func _test_traversal() -> void:
	var graph = Graph.build_from_files(_sample())
	var direct = Graph.trace(graph, "res://scenes/main.tscn", "dependencies", 1)
	_check("direct dependencies include scene", direct["nodes"].has("scenes/main.tscn"))
	_check("direct dependencies include player", direct["nodes"].has("scenes/player.tscn"))
	_check("direct dependencies include image", direct["nodes"].has("art/icon.png"))
	_check("direct dependencies exclude nested script", not direct["nodes"].has("scripts/player.gd"))
	var indirect = Graph.trace(graph, "scenes/main.tscn", "dependencies", -1)
	_check("all descendants indexed", indirect["nodes"].size() == 4)
	_check("direction dependencies does not include isolated", not indirect["nodes"].has("unused.tres"))
	var back = Graph.trace(graph, "art/icon.png", "referencers", -1)
	_check("reverse traversal finds scene", back["nodes"].has("scenes/main.tscn"))
	_check("reverse traversal finds script", back["nodes"].has("scripts/player.gd"))
	_check("reverse traversal finds parent scene via script", back["nodes"].has("scenes/player.tscn"))
	_check("reverse closure excludes unused", not back["nodes"].has("unused.tres"))
	var zero = Graph.trace(graph, "art/icon.png", "both", 0)
	_check("depth 0 returns root only", zero["nodes"].size() == 1)
	_check("depth 0 has no edges", zero["references"].is_empty())
	var one = Graph.trace(graph, "art/icon.png", "referencers", 1)
	_check("reverse depth 1 excludes scene through script", not one["nodes"].has("scenes/player.tscn"))
	var both = Graph.trace(graph, "scenes/player.tscn", "both", 1)
	_check("both directions finds parent", both["nodes"].has("scenes/main.tscn"))
	_check("both directions finds script", both["nodes"].has("scripts/player.gd"))
	_check("both directions size bounded", both["nodes"].size() == 3)
	_check("missing asset errors", Graph.trace(graph, "bad.tscn")["error"] != "")
	_check("invalid direction errors", Graph.trace(graph, "art/icon.png", "up")["error"] != "")
	_check("invalid depth errors", Graph.trace(graph, "art/icon.png", "both", -2)["error"] != "")
	var cycle = Graph.build_from_files({"a.gd": 'load("res://b.gd")', "b.gd": 'load("res://a.gd")'})
	_check("cycle traversal terminates", Graph.trace(cycle, "a.gd", "both", -1)["nodes"].size() == 2)
	_check("cycle includes both edges", Graph.trace(cycle, "a.gd", "both", -1)["references"].size() == 2)
	_check("unlimited cycle DOT deterministic", Graph.to_dot(cycle) == Graph.to_dot(cycle))
	var dot = Graph.to_dot(graph)
	_check("DOT graph header", dot.begins_with("digraph AssetReferences"))
	_check("DOT has directed edges", dot.contains('"res://scenes/main.tscn" -> "res://art/icon.png"'))
	_check("DOT includes binary node", dot.contains('"res://art/icon.png";'))
	_check("DOT quote escapes names", Graph.to_dot(Graph.build_from_files({'quote".tscn': ""})).contains('quote\\".tscn'))
	var dups = Graph.build_from_files({"a.gd": 'load("res://b.gd")\nload("res://b.gd")', "b.gd": ""})
	_check("DOT deduplicates equal edges", Graph.to_dot(dups).count(' -> ') == 1)


func _write(relative: String, contents: String) -> void:
	var path := ROOT.path_join(relative)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write test fixture " + path)
		failed += 1
		return
	file.store_string(contents)


func _cleanup(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in directory.get_directories():
		_cleanup(path.path_join(name))
	DirAccess.remove_absolute(path)


func _test_disk() -> void:
	_cleanup(ROOT)
	_check("invalid root rejected", not Graph.build_project("somewhere")["errors"].is_empty())
	_check("invalid byte limit rejected", not Graph.build_project("res://", 0)["errors"].is_empty())
	_check("missing directory has error", not Graph.build_project(ROOT)["errors"].is_empty())
	_write("scenes/main.tscn", 'path="res://images/icon.png"\npath="res://missing.png"')
	_write("images/icon.png", "binary")
	_write(".godot/ignored.gd", 'load("res://missing.tres")')
	_write("scripts/ref.gd", 'load("res://scenes/main.tscn")')
	var graph = Graph.build_project(ROOT)
	_check("disk scanner ignores .godot", not graph["nodes"].has(".godot/ignored.gd"))
	_check("disk scanner lists real files", graph["nodes"].has("scenes/main.tscn"))
	_check("disk scanner includes binary", graph["nodes"].has("images/icon.png"))
	_check("disk scanner includes script", graph["nodes"].has("scripts/ref.gd"))
	_check("disk scanner excludes missing edge", graph["references"].size() == 2)
	_check("disk scanner line correct", graph["references"][0]["line"] == 1)
	_check("disk scanner no errors", graph["errors"].is_empty())
	_check("disk scanner repeat deterministic", graph == Graph.build_project(ROOT))
	var too_small = Graph.build_project(ROOT, 1)
	_check("size limit skips references", too_small["references"].is_empty())
	_check("size limit preserves nodes", too_small["nodes"].size() == 3)
	var impact = Graph.trace(graph, "images/icon.png", "referencers", -1)
	_check("disk reverse transitive impact", impact["nodes"].size() == 3)
	_cleanup(ROOT)
