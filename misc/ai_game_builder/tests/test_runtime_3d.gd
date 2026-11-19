extends SceneTree

## Run in the isolated CI staging project after copying the 3D starter files.
## Validates instantiated scene objects and basic collectible/time-limit gameplay.

var passed := 0
var failed := 0


func _initialize() -> void:
	var packed := load("res://ai_generated/scenes/main.tscn") as PackedScene
	_check("3D starter scene loads", packed != null)
	if packed == null:
		quit(1)
		return

	var game := packed.instantiate() as Node3D
	_check("3D scene instantiates", game != null)
	if game == null:
		quit(1)
		return
	get_root().add_child(game)

	var player := game.get_node_or_null("Player") as MeshInstance3D
	var target := game.get_node_or_null("Collectible") as MeshInstance3D
	var camera := game.get_node_or_null("Camera3D") as Camera3D
	var sun := game.get_node_or_null("Sun") as DirectionalLight3D
	var overlay := game.get_node_or_null("Overlay") as CanvasLayer
	var hud := game.get_node_or_null("Overlay/HUD") as Label
	_check("player mesh exists", player != null and player.mesh != null)
	_check("collectible mesh exists", target != null and target.mesh != null)
	_check("camera exists", camera != null)
	_check("camera is active", camera != null and camera.current)
	_check("directional lighting exists", sun != null)
	_check("overlay exists", overlay != null)
	_check("HUD exists", hud != null)
	_check("floor exists", game.get_node_or_null("Floor") != null)
	_check("initial score zero", game.get("_score") == 0)
	_check("game begins unfinished", not game.get("_finished"))
	_check("HUD mentions controls", hud != null and hud.text.contains("WASD"))

	if player != null and target != null:
		for i in range(6):
			player.position = target.position
			game.call("_process", 0.0)
			_check("collect target %d" % (i + 1), game.get("_score") == i + 1)
		_check("six targets win the round", game.get("_finished"))
		_check("target hidden on victory", not target.visible)
		_check("winner HUD", hud.text.contains("You win"))
	game.queue_free()

	var timed := packed.instantiate() as Node3D
	get_root().add_child(timed)
	timed.call("_process", 95.0)
	_check("clock ends round", timed.get("_finished"))
	_check("no points awarded by time expiry", timed.get("_score") == 0)
	var timed_hud := timed.get_node_or_null("Overlay/HUD") as Label
	_check("time-out feedback", timed_hud != null and timed_hud.text.contains("Time over"))
	timed.queue_free()

	print("AI 3D runtime smoke: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(name: String, good: bool) -> void:
	if good:
		passed += 1
	else:
		failed += 1
		push_error("FAILED: %s" % name)
