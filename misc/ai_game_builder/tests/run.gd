extends SceneTree

const Validator = preload("res://addons/ai_game_builder/validator.gd")
const Planner = preload("res://addons/ai_game_builder/planner.gd")
const Writer = preload("res://addons/ai_game_builder/writer.gd")
const Inspector = preload("res://addons/ai_game_builder/inspector.gd")
const Dock = preload("res://addons/ai_game_builder/dock.gd")
const Plugin = preload("res://addons/ai_game_builder/plugin.gd")
const EndpointPolicy = preload("res://addons/ai_game_builder/endpoint_policy.gd")
const SmokeGate = preload("res://addons/ai_game_builder/smoke_gate.gd")
const SmokeCheck = preload("res://addons/ai_game_builder/smoke_check.gd")
const Starter = preload("res://addons/ai_game_builder/starter.gd")

var _total := 0
var _failed := 0


func _initialize() -> void:
	_run()
	_run_security_tests()
	_run_writer_atomic_tests()
	_run_headless_gate_tests()
	_run_offline_starter_tests()
	_check(Dock != null, "Editor dock script loads")
	_check(Plugin != null, "Editor plugin script loads")
	print("AI Game Builder: %d tests, %d failed" % [_total, _failed])
	quit(0 if _failed == 0 else 1)


func _plan(path: String = "main.tscn", content: String = "[gd_scene format=3]\n") -> Dictionary:
	return {"summary": "demo", "files": [{"path": path, "content": content}]}


func _check(condition: bool, description: String) -> void:
	_total += 1
	if not condition:
		_failed += 1
		printerr("FAIL: " + description)


func _accept(value: Variant, description: String) -> void:
	_check(Validator.validate(value).ok, description)


func _reject(value: Variant, description: String) -> void:
	_check(not Validator.validate(value).ok, description)


func _run() -> void:
	_accept(_plan(), "simple scene")
	_accept(_plan("levels/first/level_01.tscn"), "nested path")
	_accept(_plan("shader.gdshader", "shader_type canvas_item;"), "shader allowed")
	_accept(_plan("data.json", "{}"), "JSON allowed")
	_accept(_plan("README.md", "text"), "Markdown allowed")
	_accept(_plan("note.txt", "text"), "text allowed")
	_accept(_plan("scripts/player.gd", "extends Node\n"), "script allowed")
	_accept(_plan("a.tres", "[gd_resource type=\"Resource\" format=3]\n"), "resource allowed")

	_reject(null, "null plan")
	_reject([], "array plan")
	_reject({}, "files missing")
	_reject({"files": []}, "no files")
	_reject({"files": "bad"}, "files not array")
	_reject({"files": ["bad"]}, "file not dictionary")
	_reject({"files": [{"path": "a.gd"}]}, "content missing")
	_reject({"files": [{"content": "x"}]}, "path missing")
	_reject({"files": [{"path": 3, "content": "x"}]}, "path nonstring")
	_reject({"files": [{"path": "a.gd", "content": 3}]}, "content nonstring")
	_reject(_plan("../escape.gd"), "parent traversal")
	_reject(_plan("a/../escape.gd"), "nested traversal")
	_reject(_plan("./bad.gd"), "dot segment")
	_reject(_plan("/abs.gd"), "absolute path")
	_reject(_plan("res://outside.gd"), "resource path rejected")
	_reject(_plan("C:/windows.gd"), "drive path rejected")
	_reject(_plan("folder\\bad.gd"), "backslash rejected")
	_reject(_plan("double//slash.gd"), "empty segment rejected")
	_reject(_plan("hidden/.config.gd"), "hidden path rejected")
	_reject(_plan(".env"), "hidden secret file rejected")
	_reject(_plan("spaces are bad.gd"), "spaces rejected")
	_reject(_plan("café.gd"), "non-ASCII path rejected")
	_reject(_plan("a.png"), "binary extension rejected")
	_reject(_plan("evil.exe"), "executable extension rejected")
	_reject(_plan("bad.gd\n"), "trailing newline rejected")
	_reject(_plan("a\n/b.gd"), "embedded newline rejected")
	_reject(_plan("file.gd", ""), "empty content rejected")
	_reject(_plan("file.gd", "x".repeat(Validator.MAX_FILE_BYTES + 1)), "oversized file rejected")
	_reject(_plan("file.gd", "hi\u0000there"), "embedded NUL rejected")
	_reject({"summary": 5, "files": _plan().files}, "nonstring summary")
	_reject({"summary": "x".repeat(801), "files": _plan().files}, "oversized summary")
	_reject(_plan("a".repeat(161) + ".gd"), "long path rejected")
	_accept(_plan("file.gd", "x".repeat(Validator.MAX_FILE_BYTES)), "file at size limit")

	var duplicates := {"files": [{"path": "Level.tscn", "content": "a"}, {"path": "level.tscn", "content": "b"}]}
	_reject(duplicates, "case-insensitive duplicates")
	var too_many: Array = []
	for index in range(Validator.MAX_FILES + 1):
		too_many.append({"path": "f%d.gd" % index, "content": "x"})
	_reject({"files": too_many}, "too many files")
	var oversized_total: Array = []
	for index in range(5):
		oversized_total.append({"path": "f%d.gd" % index, "content": "x".repeat(Validator.MAX_FILE_BYTES)})
	_reject({"files": oversized_total}, "total byte limit")
	var at_limit: Array = []
	for index in range(4):
		at_limit.append({"path": "f%d.gd" % index, "content": "x".repeat(Validator.MAX_FILE_BYTES)})
	_accept({"files": at_limit}, "total byte limit accepted")

	_check(not Validator.parse("{broken").ok, "invalid JSON rejected")
	_check(Validator.parse(JSON.stringify(_plan())).ok, "valid JSON parsed")
	_check(not Planner.read_response("{}").ok, "empty provider response")
	_check(not Planner.read_response("invalid").ok, "invalid provider response")
	_check(not Planner.read_response("{\"choices\": [null]}").ok, "invalid choice")
	_check(not Planner.read_response("{\"choices\": [{}]}").ok, "missing message")
	_check(not Planner.read_response("{\"choices\": [{\"message\": {}}]}").ok, "missing content")
	var response := JSON.stringify({"choices": [{"message": {"content": JSON.stringify(_plan())}}]})
	_check(Planner.read_response(response).ok, "valid provider response")
	var fence := "\u0060\u0060\u0060"
	var fenced := JSON.stringify({"choices": [{"message": {"content": fence + "json\n" + JSON.stringify(_plan()) + "\n" + fence}}]})
	_check(Planner.read_response(fenced).ok, "fenced JSON response")
	var payload: Variant = JSON.parse_string(Planner.make_request("test-model", "Build a game"))
	_check(typeof(payload) == TYPE_DICTIONARY and payload.model == "test-model", "request format")
	_check(payload.messages.size() == 2, "system and user prompts")

	# Static, non-executing validation of the generated game.
	var clean_scene := _plan()
	var clean_inspection := Inspector.inspect(clean_scene)
	_check(clean_inspection.ok, "valid entry scene is accepted")
	_check(clean_inspection.errors.is_empty(), "valid entry scene has no errors")
	_check(clean_inspection.warnings.is_empty(), "simple entry scene has no warnings")

	var no_entry := Inspector.inspect(_plan("player.gd", "extends Node\n"))
	_check(not no_entry.ok, "missing main scene rejected")
	_check(no_entry.errors.size() == 1, "missing main scene reports one error")
	_check(no_entry.errors[0].contains("main.tscn"), "missing entry named in diagnostic")
	_check(not Inspector.inspect(_plan("main.tscn", "hello")).ok, "invalid scene header rejected")
	_check(not Inspector.inspect({"files": []}).ok, "malformed plan fails static inspection")

	var linked_plan := {"files": [
		{"path": "main.tscn", "content": "[gd_scene load_steps=2 format=3]\n[ext_resource type=\"Script\" path=\"res://ai_generated/scripts/player.gd\" id=\"1\"]\n"},
		{"path": "scripts/player.gd", "content": "extends Node\n"}
	]}
	_check(Inspector.inspect(linked_plan).ok, "generated local resource reference passes")
	var linked = Inspector.inspect(linked_plan)
	_check(linked.errors.is_empty(), "generated resource reference has no errors")
	_check(linked.warnings.is_empty(), "generated script has no warnings")

	var missing_dependency := _plan("main.tscn", "[gd_scene format=3]\n[ext_resource path=\"res://ai_generated/player.gd\" id=\"1\"]\n")
	_check(not Inspector.inspect(missing_dependency).ok, "missing dependency rejected")
	_check(Inspector.inspect(missing_dependency).errors[0].contains("player.gd"), "missing resource named")
	var duplicated_reference := _plan("main.tscn", "[gd_scene format=3]\n# res://ai_generated/bad.gd res://ai_generated/bad.gd\n")
	_check(Inspector.inspect(duplicated_reference).errors.size() == 1, "duplicate diagnostics deduplicated")

	var outside := _plan("main.tscn", "[gd_scene format=3]\n[ext_resource path=\"res://addons/evil.gd\" id=\"1\"]\n")
	_check(not Inspector.inspect(outside).ok, "external addon dependency rejected")
	_check(Inspector.inspect(outside).errors[0].contains("external resource"), "outside dependency explained")
	var outside_script := {"files": [
		{"path": "main.tscn", "content": "[gd_scene format=3]\n"},
		{"path": "player.gd", "content": "extends Node\nconst X = preload(\"res://outside.gd\")\n"}
	]}
	_check(not Inspector.inspect(outside_script).ok, "external script preload rejected")
	var outside_shader := {"files": [
		{"path": "main.tscn", "content": "[gd_scene format=3]\n"},
		{"path": "s.gdshader", "content": "shader_type canvas_item; // res://outside/file.gdshader"}
	]}
	_check(not Inspector.inspect(outside_shader).ok, "external shader resource rejected")
	var harmless_docs := {"files": [
		{"path": "main.tscn", "content": "[gd_scene format=3]\n"},
		{"path": "notes.md", "content": "This docs file mentions res://other/project.gd"}
	]}
	_check(Inspector.inspect(harmless_docs).ok, "resource examples in documentation ignored")
	var risky_script := {"files": [
		{"path": "main.tscn", "content": "[gd_scene format=3]\n"},
		{"path": "script.gd", "content": "@tool\nextends Node\nfunc run():\n\tOS.execute(\"x\", [])\n"}
	]}
	var warnings := Inspector.inspect(risky_script)
	_check(not warnings.ok, "generated editor tool and OS execution are blocked")
	_check(warnings.errors.size() == 2, "tool and process launch report independent errors")
	_check(warnings.warnings.is_empty(), "blocked operations do not also warn")

	var script_warnings := {"files": [
		{"path": "main.tscn", "content": "[gd_scene format=3]\n"},
		{"path": "script.gd", "content": "extends Node\nfunc save():\n\tFileAccess.open(\"user://save.txt\", FileAccess.WRITE)\n"}
	]}
	var soft_warning := Inspector.inspect(script_warnings)
	_check(soft_warning.ok, "save file API only warns")
	_check(soft_warning.warnings.size() == 1, "save operation warning surfaced")
	var process_script := {"files": [
		{"path": "main.tscn", "content": "[gd_scene format=3]\n"},
		{"path": "script.gd", "content": "extends Node\nfunc spawn():\n\tOS.create_process(\"bad\", [])\n"}
	]}
	_check(not Inspector.inspect(process_script).ok, "process creation rejected")
	var repair_text := Inspector.repair_prompt("Create a platformer", missing_dependency, Inspector.inspect(missing_dependency).errors)
	_check(repair_text.contains("Create a platformer"), "repair includes original request")
	_check(repair_text.contains("player.gd"), "repair includes missing dependency")
	_check(repair_text.contains("main.tscn"), "repair includes previous scene")
	_check(repair_text.contains("COMPLETE replacement JSON"), "repair asks for complete plan")

	var refinement := Inspector.refine_prompt("Make a runner", "Add a boss", clean_scene)
	_check(refinement.contains("Make a runner"), "refinement retains original goal")
	_check(refinement.contains("Add a boss"), "refinement includes new requested feature")
	_check(refinement.contains("main.tscn"), "refinement includes existing scene")
	_check(refinement.contains("COMPLETE replacement JSON"), "refinement requests complete plan")
	_check(refinement.contains("Preserve working features"), "refinement asks to preserve existing mechanics")


	# Writer integration runs only in the disposable test project.
	var output := "res://ai_generated/tests/generated.txt"
	var absolute := ProjectSettings.globalize_path(output)
	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(absolute)
	var result := Writer.apply(_plan("tests/generated.txt", "generated"))
	_check(result.ok, "writer creates file")
	_check(FileAccess.file_exists(output), "writer file exists")
	if FileAccess.file_exists(output):
		_check(FileAccess.get_file_as_string(output) == "generated", "writer preserves content")
		var conflict := Writer.apply(_plan("tests/generated.txt", "replacement"))
		_check(not conflict.ok, "writer refuses overwrite")
		_check(FileAccess.get_file_as_string(output) == "generated", "existing content unchanged")
		DirAccess.remove_absolute(absolute)
	_check(not Writer.apply(_plan("../escape.gd")).ok, "writer revalidates paths")

	# The output directory may contain symlinks supplied by a project author.
	# Avoid creating any file that traverses through one.
	var output_root := ProjectSettings.globalize_path("res://ai_generated/")
	var create_root := DirAccess.make_dir_recursive_absolute(output_root)
	_check(create_root == OK, "symlink test output folder exists")
	var link_path := output_root.path_join("_symlink_test")
	var link_target := ProjectSettings.globalize_path("res://")
	if DirAccess.dir_exists_absolute(link_path):
		printerr("SKIP symlink test: conflicting directory already exists.")
	else:
		var output_dir := DirAccess.open("res://ai_generated/")
		if output_dir != null:
			var create_link_error := output_dir.create_link(link_target, link_path)
			if create_link_error == OK:
				var escape_file := "res://writer_escape_proof.txt"
				_check(not Writer.apply(_plan("_symlink_test/writer_escape_proof.txt", "escape")).ok, "writer rejects symlink directory")
				_check(not FileAccess.file_exists(escape_file), "symlink escape wrote no external file")
				DirAccess.remove_absolute(link_path)
			else:
				print("SKIP symlink test: filesystem does not support creating symlinks.")



func _run_security_tests() -> void:
	# Malicious strings must never cause an HTTP request to a non-loopback host.
	# Some of these used to pass the old starts_with("http://localhost:") test.
	var safe_endpoints := [
		"https://api.openai.com/v1/chat/completions",
		"https://api.example.com",
		"https://api.example.com:443/v1/chat/completions",
		"https://api-2.example.com/v1/chat/completions",
		"https://127.0.0.1:443/v1",
		"https://[::1]:443/v1",
		"https://localhost:8443/v1/chat/completions",
		"https://api.example.com?format=json",
		"http://localhost:8080/v1/chat/completions",
		"http://localhost/v1/chat/completions",
		"http://127.0.0.1:1234/v1",
		"http://[::1]:1234/v1",
		"http://[::1]/v1",
		"http://localhost:1/v1",
		"http://localhost:65535/v1",
		"http://localhost:80/v1?stream=false",
	]
	for endpoint in safe_endpoints:
		_check(EndpointPolicy.is_allowed(endpoint), "safe endpoint accepted: " + endpoint)

	var unsafe_endpoints := [
		"",
		"http://evil.example.com/v1",
		"http://localhost.evil.com:1234/v1",
		"http://127.0.0.1.evil.com:1234/v1",
		"http://localhost:1234@evil.com/v1",
		"http://127.0.0.1:1234@evil.com/v1",
		"http://[::1]:1234@evil.com/v1",
		"http://localhost@evil.com/v1",
		"http://[::1]@evil.com/v1",
		"http://[::1].evil.com:1234/v1",
		"http://127.1:1234/v1",
		"http://0.0.0.0:1234/v1",
		"http://127.0.0.2:1234/v1",
		"http://192.168.1.2:1234/v1",
		"http://[::ffff:127.0.0.1]:1234/v1",
		"http://localhost:/v1",
		"http://localhost:0/v1",
		"http://localhost:65536/v1",
		"http://localhost:-1/v1",
		"http://localhost:80bad/v1",
		"http://localhost:00000000080/v1",
		"http://localhost:80.0/v1",
		"http://[::1/v1",
		"http://[xyz::1]:8080/v1",
		"ftp://localhost:8080/v1",
		"file:///etc/passwd",
		"HTTPS://api.example.com/v1",
		"https://",
		"https:///v1",
		"https://api.example.com:0/v1",
		"https://api.example.com:65536/v1",
		"https://api.example.com:abc/v1",
		"https://api.example.com:0000001/v1",
		"https://api.example.com@evil.com/v1",
		"https://api.example.com:443@evil.com/v1",
		"https://api_example.com/v1",
		"https://-api.example.com/v1",
		"https://api-.example.com/v1",
		"https://api..example.com/v1",
		"https://api.example.com./v1",
		"https://api%2eexample.com/v1",
		"https://api.example.com#fragment",
		"https://api.example.com/path with spaces",
		"https://api.example.com/line\nbreak",
		"https://api.example.com/line\rbreak",
		"https://api.example.com/line\tbreak",
		"https://api.example.com\\evil",
		"https://[::1]oops:443/v1",
		"https://[]:443/v1",
		"http://localhost:80/v1?receiver=user@evil.com",
	]
	for endpoint in unsafe_endpoints:
		_check(not EndpointPolicy.is_allowed(endpoint), "unsafe endpoint rejected: " + endpoint)

	for token in ["", "sk-test123", "local_token-+/=", "abc.def_ghi", "TOKEN12345"]:
		_check(EndpointPolicy.is_valid_bearer_token(token), "safe provider API key accepted")
	for token in [
		"bearer\nInjected: yes", "bearer\rInjected: yes", "bad\tkey",
		"abc def", "bad\u0000key", "bad\u007fkey", "é", "x".repeat(4097),
	]:
		_check(not EndpointPolicy.is_valid_bearer_token(token), "unsafe header value rejected")

	for filename in [
		"CON.gd", "con.backup.gd", "aux.gd", "PRN.tscn",
		"nul.md", "COM1.gd", "com9.gd", "LPT1.gd",
		"lpt9.tres", "some/AUX/level.gd", "screens/level./main.tscn",
		"a./main.tscn",
	]:
		_reject(_plan(filename, "extends Node"), "portable reserved path rejected: " + filename)
	for filename in [
		"console.gd", "auxiliary.tscn", "COM0.gd", "com10.gd",
		"lpt0.tscn", "lpt10.tscn", "some/valid.folder/main.tscn",
	]:
		_accept(_plan(filename, "extends Node"), "portable safe path accepted: " + filename)

	# Safety validation runs again at the write boundary.
	_check(not Writer.apply(_plan("CON.gd", "extends Node")).ok, "writer rejects reserved file path")
	_check(not Writer.apply(_plan("data/lpt1.backup.txt", "demo")).ok, "writer rejects nested reserved component")


func _run_writer_atomic_tests() -> void:
	# An existing destination in any position must reject the WHOLE
	# plan before the first new file is written.
	var test_dir := "res://ai_generated/tests"
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_dir)) == OK, "atomic writer test directory available")
	var preexisting := test_dir.path_join("_ai_existing.txt")
	var new_output := test_dir.path_join("_ai_should_not_exist.txt")
	for path in [preexisting, new_output]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var seed := FileAccess.open(preexisting, FileAccess.WRITE)
	_check(seed != null, "atomic writer seeded existing output")
	if seed == null:
		return
	seed.store_string("original contents")
	seed.close()

	var conflict_plan := {
		"files": [
			{"path": "tests/_ai_should_not_exist.txt", "content": "new file"},
			{"path": "tests/_ai_existing.txt", "content": "overwrite"}
		]
	}
	var before := Writer.apply(conflict_plan)
	_check(not before.ok, "multi-file writer rejects a later existing destination")
	_check(not FileAccess.file_exists(new_output), "multi-file preflight creates no earlier file")
	_check(FileAccess.get_file_as_string(preexisting) == "original contents", "multi-file preflight preserves existing contents")

	var reverse_plan := {
		"files": [
			{"path": "tests/_ai_existing.txt", "content": "overwrite"},
			{"path": "tests/_ai_should_not_exist.txt", "content": "new file"}
		]
	}
	var after := Writer.apply(reverse_plan)
	_check(not after.ok, "multi-file writer rejects an earlier existing destination")
	_check(not FileAccess.file_exists(new_output), "reverse-order preflight also creates no file")
	_check(FileAccess.get_file_as_string(preexisting) == "original contents", "reverse-order preflight preserves contents")

	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(preexisting)) == OK, "atomic writer fixture cleanup")


func _run_headless_gate_tests() -> void:
	# This runs in the standalone throwaway AI Game Builder test project only.
	# The checker uses Godot's real GDScript/scene resource loader, not just
	# text regular expressions.
	var scene_path := "res://ai_generated/main.tscn"
	var script_path := "res://ai_generated/tests/headless_valid.gd"
	var json_path := "res://ai_generated/tests/headless_valid.json"
	var invalid_json_path := "res://ai_generated/tests/headless_invalid.json"
	var paths := [scene_path, script_path, json_path, invalid_json_path]
	for target in paths:
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target))

	var sample := {"files": [
		{"path": "main.tscn", "content": "[gd_scene format=3]\n\n[node name=\"Main\" type=\"Node2D\"]\n"},
		{"path": "tests/headless_valid.gd", "content": "extends Node\nfunc answer() -> int:\n\treturn 42\n"},
		{"path": "tests/headless_valid.json", "content": "{\"name\":\"valid\",\"score\":42}"}
	]}
	var created := Writer.apply(sample)
	_check(created.ok, "headless fixture creates a real Godot scene, script and JSON data")
	if not created.ok:
		return

	var good := [scene_path, script_path, json_path]
	var valid := SmokeGate.validate_targets(good)
	_check(valid.ok, "approved resource list passes headless preflight")
	_check(valid.get("paths", []).size() == 3, "preflight preserves the three approved resources")
	var inspected := SmokeGate.check(good)
	_check(inspected.ok, "headless ResourceLoader parses generated GDScript and scene")
	_check(int(inspected.checked) == 3, "headless checker actually processed all three resources")
	_check(inspected.errors.is_empty(), "valid headless game produces no diagnostics")

	_check(not SmokeGate.validate_targets(null).ok, "null approved paths rejected")
	_check(not SmokeGate.validate_targets("main.tscn").ok, "text approved paths rejected")
	_check(not SmokeGate.validate_targets({}).ok, "object approved paths rejected")
	_check(not SmokeGate.validate_targets([]).ok, "empty approved paths rejected")
	_check(not SmokeGate.validate_targets([scene_path, 7]).ok, "nonstring approved path rejected")
	_check(not SmokeGate.validate_targets([script_path]).ok, "missing main scene rejected")
	_check(not SmokeGate.validate_targets([scene_path, scene_path]).ok, "duplicate approved path rejected")
	_check(not SmokeGate.validate_targets([scene_path, "res://ai_generated/MAIN.tscn"]).ok, "case-insensitive duplicate rejected")
	_check(not SmokeGate.validate_targets([scene_path, "res://project.godot"]).ok, "project settings outside output rejected")
	_check(not SmokeGate.validate_targets([scene_path, "res://addons/ai_game_builder/plugin.gd"]).ok, "plugin source outside output rejected")
	_check(not SmokeGate.validate_targets([scene_path, "user://secret.gd"]).ok, "user data path rejected")
	_check(not SmokeGate.validate_targets([scene_path, "/etc/passwd"]).ok, "absolute path rejected")
	_check(not SmokeGate.validate_targets([scene_path, "res://ai_generated/../escape.gd"]).ok, "traversal rejected")
	_check(not SmokeGate.validate_targets([scene_path, "res://ai_generated/.godot/metadata.gd"]).ok, "hidden path rejected")
	_check(not SmokeGate.validate_targets([scene_path, "res://ai_generated/CON.gd"]).ok, "Windows device path rejected")
	_check(not SmokeGate.validate_targets([scene_path, "res://ai_generated/missing.gd"]).ok, "nonexistent resource rejected")
	_check(not SmokeGate.validate_targets([scene_path, "res://ai_generated/main.exe"]).ok, "unsupported executable path rejected")

	var too_many: Array = [scene_path]
	for i in range(Validator.MAX_FILES):
		too_many.append("res://ai_generated/tests/not_written_%d.gd" % i)
	_check(not SmokeGate.validate_targets(too_many).ok, "file-count limit before loading unapproved files")

	for path in [
		"user://ai_game_builder/report_1.json",
		"user://ai_game_builder/check_20261119.json",
		"user://ai_game_builder/test-A_B.json"
	]:
		_check(SmokeCheck._safe_report_path(path), "safe report destination accepted: " + path)
	for path in [
		"", "res://ai_game_builder/unsafe.json", "user://other_folder/report.json",
		"user://ai_game_builder/../escape.json", "user://ai_game_builder/sub/hidden.json",
		"user://ai_game_builder/unsafe\\file.json", "user://ai_game_builder/unsafe.txt",
		"user://ai_game_builder/.json", "user://ai_game_builder/unsafe file.json",
		"user://ai_game_builder/%2e%2e.json", "user://ai_game_builder/very".repeat(40) + ".json",
	]:
		_check(not SmokeCheck._safe_report_path(path), "unsafe report destination rejected: " + path)

	var bad_created := Writer.apply({
		"files": [{"path": "tests/headless_invalid.json", "content": "{bad json"}]
	})
	_check(bad_created.ok, "invalid JSON fixture can be staged as a text asset")
	if bad_created.ok:
		var malformed := SmokeGate.check([scene_path, invalid_json_path])
		_check(not malformed.ok, "headless checker rejects malformed JSON game data")
		_check(malformed.errors.size() == 1, "invalid JSON yields one clear diagnostic")
		_check(String(malformed.errors[0]).contains("headless_invalid.json"), "JSON error includes the source filename")

	# A file can change after the AI plan was approved. The checker must
	# enforce safe content at verification time rather than trusting the plan.
	var dangerous_script := FileAccess.open(script_path, FileAccess.WRITE)
	_check(dangerous_script != null, "headless guard fixture can edit approved script")
	if dangerous_script != null:
		dangerous_script.store_string("@tool\nextends Node\n")
		dangerous_script.close()
		_check(not SmokeGate.validate_targets(good).ok, "headless preflight blocks newly added editor tool script")
		var process_script := FileAccess.open(script_path, FileAccess.WRITE)
		if process_script != null:
			process_script.store_string("extends Node\nfunc run():\n\tOS.execute(\\"sh\\", [])\n")
			process_script.close()
			_check(not SmokeGate.validate_targets(good).ok, "headless preflight blocks process launches")
		var restored_script := FileAccess.open(script_path, FileAccess.WRITE)
		if restored_script != null:
			restored_script.store_string("extends Node\nfunc answer() -> int:\n\treturn 42\n")
			restored_script.close()
			_check(SmokeGate.validate_targets(good).ok, "restored safe script accepted")

	# Oversized generated files are rejected even when they exist on disk.
	var huge_path := "res://ai_generated/tests/headless_oversized.md"
	var huge_file := FileAccess.open(huge_path, FileAccess.WRITE)
	_check(huge_file != null, "headless size-limit fixture can create a file")
	if huge_file != null:
		huge_file.store_string("x".repeat(Validator.MAX_FILE_BYTES + 1))
		huge_file.close()
		_check(not SmokeGate.validate_targets([scene_path, huge_path]).ok, "headless preflight rejects oversized existing files")
		_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(huge_path)) == OK, "oversized fixture cleaned up")

	for target in paths:
		if FileAccess.file_exists(target):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(target)) == OK, "headless test asset cleaned up")


func _run_offline_starter_tests() -> void:
	# The starter is part of the selected unified AI addon, not a separate
	# competing editor plugin. It requires neither network nor API keys.
	var draft := Starter.create_draft()
	_check(draft.ok, "offline arcade template generates without any AI provider")
	if not draft.ok:
		return
	_check(typeof(draft.plan) == TYPE_DICTIONARY, "offline starter returns the common JSON-plan schema")
	_check(draft.plan.files.size() == 3, "offline starter contains scene, script and readme")
	_check(String(draft.plan.summary).contains("Offline"), "offline starter explains its deterministic origin")

	var contents := {}
	for entry in draft.plan.files:
		contents[String(entry.path)] = String(entry.content)
	_check(contents.has("main.tscn"), "offline starter uses the canonical main scene")
	_check(contents.has("scripts/arcade.gd"), "offline starter contains complete movement logic")
	_check(contents.has("README.md"), "offline starter includes play instructions")
	_check(String(contents.get("main.tscn", "")).begins_with("[gd_scene"), "offline main scene is a Godot resource")
	_check(String(contents.get("main.tscn", "")).contains("res://ai_generated/scripts/arcade.gd"), "scene references the generated script")
	_check(String(contents.get("scripts/arcade.gd", "")).contains("KEY_W"), "arcade supports WASD movement")
	_check(String(contents.get("scripts/arcade.gd", "")).contains("KEY_RIGHT"), "arcade supports arrow-key movement")
	_check(String(contents.get("scripts/arcade.gd", "")).contains("WIN_SCORE"), "arcade has win condition and scoring")
	_check(String(contents.get("scripts/arcade.gd", "")).contains("ROUND_SECONDS"), "arcade has a round timer")
	_check(String(contents.get("scripts/arcade.gd", "")).contains("KEY_R"), "arcade supports restart")
	_check(String(contents.get("README.md", "")).contains("res://ai_generated/main.tscn"), "offline instructions point to the generated main scene")

	var plan_valid := Validator.validate(draft.plan)
	_check(plan_valid.ok, "offline files pass the same safety parser as AI responses")
	var static_result := Inspector.inspect(draft.plan)
	_check(static_result.ok, "offline template passes dependency and static security inspection")
	_check(static_result.errors.is_empty(), "offline starter has no missing generated dependencies")
	_check(static_result.warnings.is_empty(), "offline starter has no flagged risky code")
	if not plan_valid.ok or not static_result.ok:
		return

	var output_paths := [
		"res://ai_generated/main.tscn",
		"res://ai_generated/scripts/arcade.gd",
		"res://ai_generated/README.md"
	]
	for output in output_paths:
		if FileAccess.file_exists(output):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(output))
	var written := Writer.apply(draft.plan)
	_check(written.ok, "offline starter can be applied by normal review-first writer")
	if not written.ok:
		return
	_check(written.paths.size() == 3, "writer emits the three expected starter assets")
	for output in output_paths:
		_check(FileAccess.file_exists(output), "offline starter output exists: " + output)

	var resource_check := SmokeGate.check(output_paths)
	_check(resource_check.ok, "real headless Godot loader accepts offline arcade game")
	_check(resource_check.checked == 2, "real Godot loader checked the scene and GDScript")
	_check(resource_check.errors.is_empty(), "offline arcade compiles without loader diagnostics")

	var original_script := FileAccess.get_file_as_string(output_paths[1])
	var repeated := Writer.apply(draft.plan)
	_check(not repeated.ok, "offline starter refuses to overwrite an existing game")
	_check(FileAccess.get_file_as_string(output_paths[1]) == original_script, "existing starter script preserved unchanged")
	for output in output_paths:
		if FileAccess.file_exists(output):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(output)) == OK, "offline starter fixture cleaned up")
