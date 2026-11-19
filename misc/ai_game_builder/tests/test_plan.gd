extends SceneTree

const Plan = preload("res://addons/ai_game_builder/plan.gd")
const Client = preload("res://addons/ai_game_builder/ai_client.gd")
const Context = preload("res://addons/ai_game_builder/project_context.gd")
const QualityGate = preload("res://addons/ai_game_builder/quality_gate.gd")

var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var good := {"summary": "demo", "files": [{"path": "res://ai_generated/game/main.tscn", "content": "[gd_scene format=3]\n[node name=\"Main\" type=\"Node2D\"]\n"}]}
	_check(Plan.validate(good)["ok"], "valid plan")
	_check(Plan.parse_response(JSON.stringify(good))["ok"], "raw JSON")
	_check(Plan.parse_response("```json\n" + JSON.stringify(good) + "\n```")["ok"], "fenced JSON")
	_check(not Plan.parse_response("not json")["ok"], "invalid JSON")
	_check(not Plan.parse_response("{}")["ok"], "missing files")
	_check(not Plan.validate({"files": []})["ok"], "empty files")
	_check(not Plan.validate({"files": [good["files"][0], good["files"][0]]})["ok"], "duplicate path")
	_check(not Plan.validate({"files": [
		{"path": "res://ai_generated/Test.gd", "content": "pass"},
		{"path": "res://ai_generated/test.gd", "content": "pass"},
	]})["ok"], "case-insensitive duplicate")
	_check(not Plan.validate({"files": [{"path": "res://ai_generated/editor.gd", "content": "@tool\nextends Node"}]})["ok"], "reject editor-executed scripts")
	_check(not Plan.validate({"files": [{"path": "res://ai_generated/broken.json", "content": "{invalid"}]})["ok"], "reject malformed JSON")
	_check(Plan.validate({"files": [{"path": "res://ai_generated/data.json", "content": "{\"hello\":true}"}]})["ok"], "accept valid JSON")
	var scene_ref := "[gd_scene load_steps=2 format=3]\n[ext_resource type=\"Script\" path=\"res://ai_generated/missing_unique_74291.gd\" id=\"1\"]\n"
	_check(not Plan.validate({"files": [{"path": "res://ai_generated/check.tscn", "content": scene_ref}]})["ok"], "reject missing generated dependency")
	var scene_ref_valid := scene_ref.replace("missing_unique_74291.gd", "included.gd")
	_check(Plan.validate({"files": [
		{"path": "res://ai_generated/check.tscn", "content": scene_ref_valid},
		{"path": "res://ai_generated/included.gd", "content": "extends Node"},
	]})["ok"], "accept generated dependency")
	_check(QualityGate.inspect_files([{"path": "res://ai_generated/script.gd", "content": "extends Node"}]).is_empty(), "safe source")
	_check(not Plan.validate({"files": [{"path": "res://ai_generated/empty.gd", "content": ""}]})["ok"], "empty content")
	_check(not Plan.validate({"files": [{"path": "res://ai_generated/huge.gd", "content": "x".repeat(90001)}]})["ok"], "oversized content")
	_check(not Plan.validate({"files": [{"path": "res://ai_generated/a.gd", "content": 1}]})["ok"], "invalid content type")
	_check(not Plan.validate({"files": [{"path": "res://ai_generated/a.gd"}]})["ok"], "missing content")
	_check(not Plan.validate({"files": [{"path": "res://ai_generated/a.gd", "content": "ok"}], "summary": 123})["ok"], "invalid summary type")

	var many: Array = []
	for i in range(17):
		many.append({"path": "res://ai_generated/file%d.gd" % i, "content": "pass"})
	_check(not Plan.validate({"files": many})["ok"], "too many files")

	for bad_path in [
		"res://project.godot",
		"res://ai_generated/../addons/evil.gd",
		"res://ai_generated/a//b.gd",
		"res://ai_generated/a\\b.gd",
		"res://ai_generated/.hidden.gd",
		"res://ai_generated/file.exe",
		"res://ai_generated/a:b.gd",
		"res://ai_generated/a b.gd",
		"res://ai_generated/CON.gd",
		"res://ai_generated/",
	]:
		_check(not Plan.path_error(bad_path).is_empty(), "reject path " + bad_path)

	_check(Plan.path_error("res://ai_generated/levels/level_01.tscn").is_empty(), "nested valid path")
	_check(Client.is_allowed_endpoint("https://api.openai.com/v1/chat/completions"), "https endpoint")
	_check(Client.is_allowed_endpoint("http://127.0.0.1:11434/v1/chat/completions"), "local endpoint")
	_check(not Client.is_allowed_endpoint("http://example.com/v1/chat/completions"), "reject plaintext remote")
	_check(not Client.is_allowed_endpoint("https://user:pass@example.com/v1/chat/completions"), "reject URL credentials")
	_check(not Client.is_allowed_endpoint("https://example.com/?key=secret"), "reject query token")
	_check(Client.extract_text({"choices": [{"message": {"content": "{}"}}]}) == "{}", "extract text")
	_check(Client.extract_text({"choices": []}).is_empty(), "empty choices")
	_check(not Context.describe().is_empty(), "context builds")
	_check(not Context._is_selected_path_safe("res://project.godot"), "reject project settings context")
	_check(not Context._is_selected_path_safe("user://secrets.gd"), "reject external directory context")
	_check(not Context._is_selected_path_safe("res://../secrets.gd"), "reject traversal in context")
	_check(Context._is_selected_path_safe("res://tests/selected.gd"), "allow selected GDScript path")
	_check(Context.describe_selected(PackedStringArray(["res://project.godot"])).contains("no readable"), "do not share project settings")
	var selected_file := "res://ai_generated/_ai_builder_selected_context.gd"
	DirAccess.make_dir_recursive_absolute("res://ai_generated")
	var selected_stream := FileAccess.open(selected_file, FileAccess.WRITE)
	_check(selected_stream != null, "create selected context fixture")
	if selected_stream != null:
		selected_stream.store_string("extends Node\nconst CONTEXT_MARKER = 42\n")
		selected_stream.close()
		var selection := Context.describe_selected(PackedStringArray([selected_file, "res://project.godot"]))
		_check(selection.contains("CONTEXT_MARKER = 42"), "include explicitly selected content")
		_check(not selection.contains("config_version"), "exclude other file types")
		DirAccess.remove_absolute(selected_file)

	var output := "res://ai_generated/_ai_builder_regression_test.gd"
	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)
	var write_plan := {"summary": "write", "files": [{"path": output, "content": "extends Node\n"}]}
	var written := Plan.apply(write_plan)
	_check(written["ok"], "create file")
	_check(FileAccess.file_exists(output), "created file exists")
	if FileAccess.file_exists(output):
		var read_back := FileAccess.get_file_as_string(output)
		_check(read_back == "extends Node\n", "file content")
		_check(not Plan.apply(write_plan)["ok"], "prevent overwrite")
		DirAccess.remove_absolute(output)

	print("AI Game Builder tests: %d failures" % _failed)
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, title: String) -> void:
	if not condition:
		_failed += 1
		push_error("FAILED: " + title)
