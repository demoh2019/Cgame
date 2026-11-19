extends SceneTree

const Context = preload("res://addons/ai_game_builder/context.gd")
const ROOT := "tests/_ai_context/"
var checks := 0
var failures := 0


func _initialize() -> void:
	_run()
	_cleanup()
	print("AI Context tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)


func _create(relative: String, body: String) -> void:
	var absolute := "res://" + relative
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		_expect(false, "fixture writable: " + relative)
		return
	file.store_string(body)
	file.close()


func _run() -> void:
	_expect(Context.collect("")["ok"], "empty opt-in list")
	_expect(Context.collect("\n  \n")["files"].is_empty(), "empty list does not read project")
	_expect(not Context.collect("res://tests/example.gd")["ok"], "reject res:// prefix")
	_expect(not Context.collect("../../outside.gd")["ok"], "reject traversal")
	_expect(not Context.collect("addons/ai_game_builder/plugin.gd")["ok"], "reject addon files")
	_expect(not Context.collect("project.godot")["ok"], "reject project settings")
	_expect(not Context.collect(ROOT + "missing.gd")["ok"], "reject missing file")
	_expect(not Context.collect(ROOT + "credentials.json")["ok"], "reject suspicious credential name")
	_expect(not Context.collect(ROOT + "access_token.txt")["ok"], "reject suspicious token name")

	var script := ROOT + "player.gd"
	_create(script, "extends Node\nvar score := 0\n")
	var result: Dictionary = Context.collect(script)
	_expect(result["ok"], "load explicitly selected script")
	if result["ok"]:
		_expect(result["files"].size() == 1, "one file included")
		_expect(result["files"][0]["path"] == script, "relative path included")
		_expect(result["files"][0]["content"].contains("score"), "script contents included")
		_expect(result["total_bytes"] > 0, "reports byte count")
	_expect(not Context.collect(script + "\n" + script)["ok"], "reject duplicate path")
	_expect(not Context.collect(script + "\n" + script.to_upper())["ok"], "reject case-insensitive duplicate")
	_expect(not Context.collect(ROOT + "missing.gd\n" + script)["ok"], "reject before partial send")

	var unicode_path := ROOT + "dialogue.txt"
	var unicode_text := "Привет, 世界! 🌳\n"
	_create(unicode_path, unicode_text)
	result = Context.collect(unicode_path)
	_expect(result["ok"], "UTF-8 context")
	if result["ok"]:
		_expect(result["files"][0]["content"] == unicode_text, "UTF-8 round trip")

	var secret_path := ROOT + "source.txt"
	_create(secret_path, "authorization: bearer leak\n")
	_expect(not Context.collect(secret_path)["ok"], "reject obvious bearer token")
	_create(secret_path, "const api_key = 'secret'\n")
	_expect(not Context.collect(secret_path)["ok"], "reject obvious API key")
	_create(secret_path, "regular public source text\n")
	_expect(Context.collect(secret_path)["ok"], "permit benign text after edit")

	var oversized := ROOT + "oversized.txt"
	_create(oversized, "x".repeat(Context.MAX_FILE_BYTES + 1))
	_expect(not Context.collect(oversized)["ok"], "reject individual oversized context")
	var selected := ""
	for i in range(9):
		var path := ROOT + "part_%d.txt" % i
		_create(path, "ok")
		selected += path + "\n"
	_expect(not Context.collect(selected)["ok"], "reject more than eight context files")

	for i in range(4):
		_create(ROOT + "large_%d.txt" % i, "x".repeat(14000))
	var total_files := ""
	for i in range(4):
		total_files += ROOT + "large_%d.txt\n" % i
	_expect(not Context.collect(total_files)["ok"], "reject total > 48KiB")

	var nul_path := ROOT + "nul.txt"
	_create(nul_path, "a\u0000b")
	_expect(not Context.collect(nul_path)["ok"], "reject NUL/binary content")

	var invalid_path := ROOT + "invalid.txt"
	var data := PackedByteArray([255, 254, 253])
	var bad_file := FileAccess.open("res://" + invalid_path, FileAccess.WRITE)
	if bad_file != null:
		bad_file.store_buffer(data)
		bad_file.close()
		_expect(not Context.collect(invalid_path)["ok"], "reject invalid UTF-8")

	var context_link := ROOT + "linked.gd"
	var access := DirAccess.open("res://" + ROOT)
	if access != null and access.create_link("player.gd", "linked.gd") == OK:
		_expect(not Context.collect(context_link)["ok"], "reject symlinked project context")
		DirAccess.remove_absolute("res://" + context_link)


func _cleanup() -> void:
	var files := DirAccess.get_files_at("res://" + ROOT)
	for filename in files:
		DirAccess.remove_absolute("res://" + ROOT + filename)
	DirAccess.remove_absolute("res://" + ROOT)
