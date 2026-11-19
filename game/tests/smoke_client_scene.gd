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
		ok = ok and game.get_node_or_null("SafeStash") != null
		ok = ok and game.get("_recipes").has("axe_2")
		ok = ok and game.get("_recipes").has("jacket_4")
		ok = ok and game.get_node("HUD/Stats").text.contains("PROFESSIONS")
		ok = ok and game.get_node("HUD/Stats").text.contains("CARRY")
		ok = ok and game.get_node_or_null("HUD/BankPanel/Contents") != null
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
			# The local HUD must call the authoritative server's bank transfer.
			player.inventory.add("wood_1", 5)
			var opening: bool = bool(game.call("_toggle_bank"))
			ok = ok and opening and game.get_node("HUD/BankPanel").visible
			game.set("_selected_bank_item", "wood_1")
			var carry_before: int = player.inventory.count("wood_1")
			var carry_kg_before: float = player.inventory.total_weight()
			var stored_before: int = player.stash.count("wood_1")
			var deposited: bool = bool(game.call("_bank_transfer", true, 3))
			ok = ok and deposited
			ok = ok and player.inventory.count("wood_1") == carry_before - 3
			ok = ok and player.inventory.total_weight() < carry_kg_before
			ok = ok and player.stash.count("wood_1") == stored_before + 3
			var withdrawn: bool = bool(game.call("_bank_transfer", false, 2))
			ok = ok and withdrawn
			ok = ok and player.inventory.count("wood_1") == carry_before - 1
			ok = ok and player.stash.count("wood_1") == stored_before + 1
			# No client-side menu state can bypass the real distance guard.
			player.position = Vector3(120, sim.world.height_at(120.0, 0.0), 0)
			ok = ok and not bool(game.call("_bank_transfer", true, 1))
			ok = ok and player.stash.count("wood_1") == stored_before + 1
			game.call("_update_hud")
			ok = ok and not game.get_node("HUD/BankPanel").visible
	game.queue_free()
	await process_frame
	if ok:
		print("PASS: game boots local authoritative world, crafting and safe-hub stash")
	else:
		push_error("Main game entrypoint or simulation failed")
	quit(0 if ok else 1)
