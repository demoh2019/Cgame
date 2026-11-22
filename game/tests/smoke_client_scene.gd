extends SceneTree
## Run: godot --headless --path game --script res://tests/smoke_client_scene.gd
## Loads the game's entry scene (project main scene, scripts/client/online_main.tscn) and checks it builds the
## 3D world shell and the title/connect screen without errors. Gameplay itself runs on the shared GameServer
## and is covered by the run_all.gd suites; joining a world needs a server and is covered by e2e tests.

const ENTRY := "res://scripts/client/online_main.tscn"


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene != ENTRY:
		push_error("Project main scene is %s, expected %s (one game client)" % [main_scene, ENTRY])
		quit(1)
		return
	var packed := load(ENTRY) as PackedScene
	if packed == null:
		push_error("Game entry scene cannot be loaded")
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	for frame in range(10):
		await process_frame
	var problems: PackedStringArray = []
	if not (game.get("camera") is Camera3D):
		problems.append("no 3D camera")
	if not (game.get("connect_panel") is PanelContainer) or not (game.get("connect_panel") as Control).visible:
		problems.append("title/connect screen not shown")
	if not (game.get("name_edit") is LineEdit):
		problems.append("no survivor name field")
	if game.get("effects") == null:
		problems.append("no effects layer")
	if not problems.is_empty():
		push_error("Client smoke failed: " + ", ".join(problems))
		quit(1)
		return
	print("CLIENT SMOKE OK: %s builds its world shell and title screen" % ENTRY)
	game.queue_free()
	await process_frame
	quit(0)
