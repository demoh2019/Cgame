extends SceneTree
## Engine-level regression for actual game logic and playable world.
## Usage: godot --headless --path demo/afterfall_frontier --script res://smoke_test.gd

const Rules = preload("res://rules.gd")
const Survivor = preload("res://survivor.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _test_rules() -> void:
	_check(Rules.zone_index(150.0) == 0, "Haven zone x")
	_check(Rules.zone_index(700.0) == 1, "Frontier zone x")
	_check(Rules.zone_index(1500.0) == 2, "Deadlands zone x")
	_check(not bool(Rules.ZONES[0]["pvp"]), "Haven non-PvP")
	_check(bool(Rules.ZONES[2]["full_loot"]), "Deadlands full loot")
	_check(Rules.gathering_yield(2, 0) > Rules.gathering_yield(0, 0),
			"Risk-based gathering rewards")
	_check(Rules.profession_level(240) > Rules.profession_level(0),
			"Classless profession progression")
	_check(Rules.sanitize_bag({"wood": 500, "invalid": 2, "water": -3}) ==
			{"wood": 99}, "Save-item whitelist and caps")


func _test_crafting_and_shelter() -> void:
	var s = Survivor.new()
	var before_weight: int = s.total_weight()
	var message: String = s.craft("axe", false)
	_check(message.begins_with("Crafted"), "Starter can craft axe without station")
	_check(s.count("axe") == 1 and s.count("wood") == 1 and s.count("stone") == 0,
			"Crafting atomically consumes proper recipe")
	_check(s.total_weight() < before_weight, "Crafting changes carried weight")
	_check(s.craft("spear", false).begins_with("Requires"),
			"Advanced recipes require a workbench")
	_check(s.craft("armor", true).begins_with("Missing"),
			"Recipe requires resources")
	_check(s.gather("ore").begins_with("Requires"), "Mining needs a pickaxe")
	_check(s.gather("wood").begins_with("+"), "Wood gathering yields an item")
	_check(int(s.skills["gathering"]) > 0, "Gathering awards profession XP")
	_check(s.count("wood") > 1, "Axe adds wood gathering yield")

	var builder = Survivor.new()
	_check(builder.give("wood", 20), "Can carry building wood")
	_check(builder.give("stone", 15), "Can carry building stone")
	_check(builder.build_shelter(false).begins_with("Build in"),
			"No building outside Haven")
	_check(builder.build_shelter(true).begins_with("Shelter upgraded"),
			"First shelter built from collected resources")
	_check(builder.shelter_level == 1, "Shelter level persisted")
	_check(builder.store("wood", 3), "Shelter stash accepts materials")
	_check(builder.withdraw("wood", 1), "Shelter stash releases materials")
	_check(int(builder.stash.get("wood", 0)) == 2, "Stash keeps remaining amount")


func _test_survival_economy_and_death() -> void:
	var s = Survivor.new()
	_check(s.consume("food").begins_with("Ate"), "Food restores hunger")
	_check(s.consume("water").begins_with("Drank"), "Water restores thirst")
	_check(s.sell("wood", 1, false).begins_with("Trade only"),
			"Vendor restricted to settlement")
	var start_coins: int = s.coins
	_check(s.sell("wood", 1, true).begins_with("Sold"), "Sell resources at market")
	_check(s.coins > start_coins, "Trading pays taxed coins")
	_check(s.buy("water", 1, true).begins_with("Bought"),
			"Buy essential supplies at fixed prototype price")
	_check(s.damage(20.0) == false and s.health == 80.0, "Combat damage")
	_check(s.give("armor", 1), "Armor can be acquired")
	s.damage(20.0)
	_check(s.health == 67.0, "Equipped armor mitigates incoming damage")
	_check(s.attack_damage() == 9.0, "No class: weapon determines combat")

	var safe_model = Survivor.new()
	var safe_bag: Dictionary = safe_model.inventory.duplicate(true)
	safe_model.zone = 0
	_check(safe_model.respawn().is_empty(), "Safe-zone death does not drop items")
	_check(safe_model.inventory == safe_bag, "Safe inventory survives death")
	safe_model.zone = 1
	_check(not safe_model.respawn().is_empty(), "Contested death drops partial loot")

	var high_risk = Survivor.new()
	high_risk.shelter_level = 1
	_check(high_risk.store("wood", 2), "Prepare safe stash")
	var stored: Dictionary = high_risk.stash.duplicate(true)
	high_risk.zone = 2
	_check(not high_risk.respawn().is_empty(), "Deadlands drop all carried items")
	_check(high_risk.inventory.is_empty(), "Deadlands full-loot backpack")
	_check(high_risk.stash == stored, "Secure shelter stash survives high-risk death")


func _test_save_roundtrip() -> void:
	var original = Survivor.new()
	original.skills["gathering"] = 150
	original.coins = 75
	original.shelter_level = 2
	original.infected_kills = 4
	original.zone = 2
	_check(original.give("scrap", 3), "Add item before save")
	var saved: Dictionary = original.snapshot()
	var loaded = Survivor.new()
	_check(loaded.import_snapshot(saved), "Can import own profile snapshot")
	_check(loaded.snapshot() == saved, "Lossless valid profile snapshot roundtrip")
	var bad: Dictionary = saved.duplicate(true)
	bad["version"] = 999
	_check(not loaded.import_snapshot(bad), "Save version guard")
	bad = saved.duplicate(true)
	bad["inventory"]["impossible_item"] = 100
	_check(loaded.import_snapshot(bad), "Unknown items ignored on load")
	_check(loaded.count("impossible_item") == 0, "No arbitrary item IDs on load")
	bad = saved.duplicate(true)
	bad["inventory"] = {"wood": 1000000}
	_check(not loaded.import_snapshot(bad) or loaded.count("wood") <= 99,
			"No unlimited inventory from forged saves")


func _run() -> void:
	_test_rules()
	_test_crafting_and_shelter()
	_test_survival_economy_and_death()
	_test_save_roundtrip()

	var packed := load("res://main.tscn") as PackedScene
	_check(packed != null, "Main game scene must load")
	if packed != null:
		var world := packed.instantiate()
		root.add_child(world)
		for frame in range(12):
			await physics_frame
		_check(world.get_node_or_null("PlayerCamera") != null, "Camera is live")
		_check(world.get_node_or_null("HUD") != null, "Game HUD exists")
		_check(world.resource_nodes.size() >= 150, "All zones have resource nodes")
		_check(world.infected.size() >= 15, "Infected AI spawned")
		_check(world.survivor.zone == 0, "Player starts in Haven")
		_check(world.survivor.health > 0.0, "Survivor lives through boot")
		world.player_position = world.resource_nodes[0]["pos"]
		world.survivor.zone = 0
		var previous_xp: int = int(world.survivor.skills["gathering"])
		world._gather_or_recover()
		_check(int(world.survivor.skills["gathering"]) > previous_xp,
				"Live E interaction gathers a resource")
		world.player_position = Vector2(1300.0, 450.0)
		for frame in range(3):
			await physics_frame
		_check(world.survivor.zone == 2, "Movement updates high-risk zone")
		# Verify that the live world really creates the recoverable
		# full-loot death bag, then lets the player take those items back.
		var carried_before: Dictionary = world.survivor.inventory.duplicate(true)
		world._handle_death()
		_check(world.survivor.zone == 0, "Real death respawns in Haven")
		_check(world.player_position == Vector2(240.0, 525.0),
				"Real death restores settlement spawn location")
		_check(world.lost_bags.size() == 1, "Full-loot zone creates dropped bag")
		_check(world.survivor.inventory.is_empty(), "Real full-loot death empties bag")
		if world.lost_bags.size() == 1:
			world.player_position = world.lost_bags[0]["pos"]
			world.survivor.zone = 2
			world._gather_or_recover()
			_check(world.lost_bags.is_empty(), "Interaction can recover death bag")
			_check(world.survivor.inventory == carried_before,
					"Recovered backpack restores dropped loot without duplication")
		world.queue_free()

	if failures.is_empty():
		print("PASS: Afterfall Frontier survival/crafting/base/economy/loot game and scene")
		quit(0)
	else:
		printerr("FAIL: Afterfall Frontier smoke had %d errors" % failures.size())
		quit(1)
