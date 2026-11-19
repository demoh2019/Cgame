extends SceneTree

const Context = preload("res://addons/ai_game_builder/context.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	_check("valid relative path", Context.parse_paths("tests/fixtures/sample.gd")["ok"])
	_check("valid resource path", Context.parse_paths("res://tests/fixtures/sample.gd")["ok"])
	_check("two files parsed", Context.parse_paths("tests/fixtures/sample.gd\nREADME.md")["paths"].size() == 2)
	_check("empty lines ignored", Context.parse_paths("\nREADME.md\n\n")["paths"].size() == 1)
	_check("empty input rejected", not Context.parse_paths("")["ok"])
	_check("traversal rejected", not Context.parse_paths("../README.md")["ok"])
	_check("absolute path rejected", not Context.parse_paths("/etc/passwd.txt")["ok"])
	_check("Windows path rejected", not Context.parse_paths("C:\\keys.txt")["ok"])
	_check("addon sources blocked", not Context.parse_paths("addons/tool.gd")["ok"])
	_check("generated outputs blocked", not Context.parse_paths("ai_generated/a.gd")["ok"])
	_check("project config blocked", not Context.parse_paths("project.godot")["ok"])
	_check("secrets blocked", not Context.parse_paths("config/secrets.txt")["ok"])
	_check("password files blocked", not Context.parse_paths("config/passwords.txt")["ok"])
	_check("API keys blocked", not Context.parse_paths("config/api_key.json")["ok"])
	_check("tokens blocked", not Context.parse_paths("config/token.json")["ok"])
	_check("duplicate exact rejected", not Context.parse_paths("README.md\nREADME.md")["ok"])
	_check("duplicate case rejected", not Context.parse_paths("README.md\nreadme.md")["ok"])
	_check("limit rejected", not Context.parse_paths(_many_files())["ok"])
	_check("unsupported extension rejected", not Context.parse_paths("test.exe")["ok"])
	_check("hidden file rejected", not Context.parse_paths(".env.txt")["ok"])
	_check("missing file rejected", not Context.read_selected_paths("tests/fixtures/missing.gd")["ok"])
	var valid := Context.read_selected_paths("tests/fixtures/sample.gd")
	_check("read fixture", valid["ok"])
	_check("read is content-bearing", valid["files"].size() == 1 and valid["files"][0]["content"].contains("extends Node"))
	_check("read multiple fixtures", Context.read_selected_paths("tests/fixtures/sample.gd\nREADME.md")["files"].size() == 2)
	_check("not a symlink", not Context.has_symlink_components("tests/fixtures/sample.gd"))

	print("AI Game Builder context tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _many_files() -> String:
	var items := PackedStringArray()
	for i in range(Context.MAX_CONTEXT_FILES + 1):
		items.append("test%d.gd" % i)
	return "\n".join(items)


func _check(name: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("FAILED: %s" % name)
