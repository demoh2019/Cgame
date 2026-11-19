extends SceneTree
## Run: godot --headless --path game --script res://tests/smoke_client_scene.gd

func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var packed := load("res://scripts/client/client_main.tscn") as PackedScene
	if packed == null:
		push_error("Game entry scene cannot be loaded")
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	for frame in range(5):
		await physics_frame
	var sim = game.get("sim")
	var ok: bool = sim != null
	if ok:
		ok = sim.players.has(2)
		ok = ok and game.get_node_or_null("Camera3D") != null
		ok = ok and game.get_node_or_null("HUD/Stats") != null
		ok = ok and game.get_node_or_null("HUD/Instructions") != null
		ok = ok and game.get_node_or_null("Survivor") != null
		ok = ok and game.get("_chunks").size() >= 1
		if ok:
			var player = sim.players[2]
			var before: float = player.survival.hunger
			sim.tick(1.0)
			ok = player.survival.hunger < before
			# Use the SAME crafting backend as the dedicated server.
			player.inventory.add("wood_1", 4)
			player.position = Vector3(9, sim.world.height_at(9.0, 0.0), 0)
			var res: Dictionary = sim.cmd_craft(2, "plank_1", 2)
			ok = ok and bool(res.get("ok", false))
			ok = ok and player.inventory.count("plank_1") == 2
	game.queue_free()
	await process_frame
	if ok:
		print("PASS: game bootstraps local authoritative world and crafting")
	else:
		push_error("Main game entrypoint or simulation failed")
	quit(0 if ok else 1)
