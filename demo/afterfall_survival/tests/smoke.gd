extends SceneTree
## Run with: godot --headless --path demo/afterfall_survival --script res://tests/smoke.gd

const Rules = preload("res://scripts/rules.gd")


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> bool:
	if not condition:
		push_error("AFTERFALL SMOKE FAILED: " + label)
	return condition


func _run() -> void:
	var success := true
	var stock := {"wood": 5, "scrap": 2, "stone": 3, "cloth": 0, "berries": 0, "water": 0}
	success = _check(Rules.can_craft(stock, "spear"), "spear is craftable") and success
	success = _check(Rules.craft(stock, "spear"), "craft succeeds") and success
	success = _check(int(stock.get("wood", 0)) == 2 and int(stock.get("spear", 0)) == 1, "craft consumes and creates") and success
	success = _check(not Rules.craft(stock, "spear"), "cannot craft without wood") and success
	success = _check(not Rules.craft(stock, "unknown"), "unknown recipe rejected") and success
	var lost: Dictionary = Rules.lose_unsecured_supplies(stock)
	success = _check(int(stock["stone"]) == 2 and int(lost["stone"]) == 1, "death drop halves unsecured materials") and success
	success = _check(Rules.survival_speed_multiplier(0.0, 100.0) < 1.0, "starvation slows player") and success

	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	success = _check(game.player != null and is_instance_valid(game.player), "player spawns") and success
	success = _check(game.enemies.size() > 0, "infected spawn") and success
	success = _check(game.resource_nodes.size() > 50, "resources generated") and success
	success = _check(game.is_safe_at(game.player.position), "refuge is safe") and success

	# Put the player next to the first resource; validate real world/inventory integration.
	var amount_before: int = int(game.inventory["wood"])
	game.player.position = game.resource_nodes[0]["position"]
	success = _check(game.try_gather(), "collect nearby resource") and success
	success = _check(int(game.inventory["wood"]) > amount_before, "inventory updated by gather") and success

	# Combat is real gameplay, not only data-driven planning.
	var infected = game.enemies[0]
	infected.position = game.player.position + Vector2(23, 0)
	var hp_before: int = infected.hp
	success = _check(game.try_attack(), "attack in weapon range") and success
	success = _check(infected.hp < hp_before, "infected takes damage") and success

	# Camp building consumes resources and increases safe zones.
	game.inventory["wood"] = 5
	game.inventory["stone"] = 3
	game.selected_recipe = 3
	var camp_count: int = game.safe_camps.size()
	success = _check(game.try_craft(), "craft campfire") and success
	success = _check(game.safe_camps.size() == camp_count + 1, "build new safe camp") and success

	game.queue_free()
	await process_frame
	if success:
		print("AFTERFALL SMOKE PASSED: rules, generation, harvesting, combat, survival")
		quit(0)
	else:
		quit(1)
