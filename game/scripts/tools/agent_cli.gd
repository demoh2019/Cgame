extends SceneTree
## Agent-facing command line: compact JSON on stdout, no editor needed.
##
##   godot --headless --path game --script res://scripts/tools/agent_cli.gd -- <command> [args]
##
## Commands (all print ONE line of JSON, exit code 0 = ok / 1 = problems / 2 = usage error):
##   check <paths|all>        parse-check GDScript files/dirs (warnings are errors), errors with line numbers
##   tests <suites|all>       run suites in a child process, print a summary (--json is accepted, always JSON)
##   classes <filter>         ClassDB class names containing the filter
##   api <Name> [member]      ClassDB reflection for a class, or the public API of scripts/**/<Name>.gd
##   map [--full]             compact project map (folders, addons, modules, test suites)
##   find <symbol>            where a func/const/class/signal is defined (GDScript + modules/cgame_* C++)
##   grep <text> [--ext .gd] [--regex] [--dir res://scripts]   limited text search over the project
##   native-status            which modules/cgame_* classes exist in this binary and which facades fall back
##   suites                   list test suites with assertion counts
##   help                     this list as JSON

const Lib = preload("res://scripts/tools/agent_lib.gd")


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var flags: Dictionary = {}
	var pos: Array[String] = []
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		if a == "--ext" or a == "--dir" or a == "--limit":
			if i + 1 < args.size():
				flags[a.trim_prefix("--")] = args[i + 1]
			i += 2
			continue
		if a.begins_with("--"):
			flags[a.trim_prefix("--")] = true
		else:
			pos.append(a)
		i += 1
	if pos.is_empty():
		_emit({"error": "missing command", "commands": _commands()}, 2)
		return
	var cmd: String = pos[0]
	var rest: Array = pos.slice(1)
	var limit: int = int(flags.get("limit", 0))
	match cmd:
		"check":
			var r: Dictionary = Lib.check_scripts(rest if not rest.is_empty() else ["all"])
			_emit(r, 0 if int(r["failed"]) == 0 else 1)
		"tests":
			var r: Dictionary = Lib.run_tests(rest)
			_emit(r, 0 if bool(r["ok"]) else 1)
		"suites":
			_emit({"suites": Lib.list_suites()}, 0)
		"classes":
			_emit(Lib.classes(str(rest[0]) if not rest.is_empty() else "", limit if limit > 0 else 60), 0)
		"api":
			if rest.is_empty():
				_emit({"error": "usage: api <ClassName|script> [member-filter]"}, 2)
			else:
				var r: Dictionary = Lib.api(str(rest[0]), str(rest[1]) if rest.size() > 1 else "", limit if limit > 0 else 80)
				_emit(r, 1 if r.has("error") else 0)
		"map":
			_emit(Lib.project_map(flags.has("full")), 0)
		"find":
			if rest.is_empty():
				_emit({"error": "usage: find <symbol>"}, 2)
			else:
				_emit(Lib.find_symbol(str(rest[0]), limit if limit > 0 else 40), 0)
		"grep":
			if rest.is_empty():
				_emit({"error": "usage: grep <text> [--ext .gd] [--regex] [--dir res://scripts]"}, 2)
			else:
				_emit(Lib.search_project(str(rest[0]), str(flags.get("ext", "")), limit if limit > 0 else 40,
					flags.has("regex"), str(flags.get("dir", "res://"))), 0)
		"native-status":
			_emit(Lib.native_status(), 0)
		"help":
			_emit({"commands": _commands()}, 0)
		_:
			_emit({"error": "unknown command '%s'" % cmd, "commands": _commands()}, 2)


func _commands() -> Array[String]:
	return ["check <paths|all>", "tests <suites|all>", "suites", "classes <filter>", "api <Name> [member]",
		"map [--full]", "find <symbol>", "grep <text> [--ext .gd] [--regex] [--dir res://x]", "native-status", "help"]


func _emit(data: Dictionary, code: int) -> void:
	print(JSON.stringify(data))
	quit(code)
