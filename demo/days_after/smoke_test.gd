extends SceneTree

## Run with a compiled Cgame editor:
## ./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test.gd

func _initialize() -> void:
    call_deferred("_run")


func _expect(condition: bool, message: String) -> bool:
    if condition:
        return true
    push_error("Days After smoke: " + message)
    quit(1)
    return false


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if not _expect(scene != null, "main scene loads"):
        return
    var game := scene.instantiate()
    root.add_child(game)

    var survivor := game.get_node_or_null("Player") as CharacterBody3D
    var food = game.get_node_or_null("FoodCrate")
    var water = game.get_node_or_null("WaterCan")
    var ground = game.get_node_or_null("Ground")
    var wood_a = game.get_node_or_null("WoodPileA")
    var wood_b = game.get_node_or_null("WoodPileB")
    var wood_c = game.get_node_or_null("WoodPileC")
    var stone_a = game.get_node_or_null("ScrapStoneA")
    var stone_b = game.get_node_or_null("ScrapStoneB")
    var fiber_a = game.get_node_or_null("FiberBushA")
    var fiber_b = game.get_node_or_null("FiberBushB")
    var dense_wood = game.get_node_or_null("DenseWood")
    var hard_stone = game.get_node_or_null("HardStone")
    var strong_fiber = game.get_node_or_null("StrongFiber")
    var infected = game.get_node_or_null("InfectedSouth")
    if not _expect(survivor != null and food != null and water != null
            and ground is StaticBody3D and wood_a != null and wood_b != null
            and wood_c != null and stone_a != null and stone_b != null
            and fiber_a != null and fiber_b != null and dense_wood != null
            and hard_stone != null and strong_fiber != null and infected != null,
            "gameplay nodes and collisions exist"):
        return

    food.call("interact", survivor)
    food.call("interact", survivor)
    water.call("interact", survivor)
    if not _expect(int(survivor.call("get_item_count", "food")) == 2
            and int(survivor.call("get_item_count", "water")) == 1,
            "pickups cannot duplicate loot"):
        return
    survivor.set("hunger", 20.0)
    survivor.set("thirst", 10.0)
    survivor.call("consume_food")
    survivor.call("consume_water")
    if not _expect(int(survivor.call("get_item_count", "food")) == 1
            and int(survivor.call("get_item_count", "water")) == 0
            and float(survivor.get("hunger")) >= 55.0
            and float(survivor.get("thirst")) >= 55.0,
            "consumption spends items and restores survival"):
        return

    wood_a.call("interact", survivor)
    wood_a.call("interact", survivor)
    wood_b.call("interact", survivor)
    wood_c.call("interact", survivor)
    stone_a.call("interact", survivor)
    stone_b.call("interact", survivor)
    fiber_a.call("interact", survivor)
    fiber_b.call("interact", survivor)
    if not _expect(int(survivor.call("get_item_count", "wood_t1")) == 6
            and int(survivor.call("get_item_count", "stone_t1")) == 4
            and int(survivor.call("get_item_count", "fiber_t1")) == 4,
            "each tier-1 deposit grants precisely one yield"):
        return

    var wood_before := int(survivor.call("get_item_count", "wood_t2"))
    if not _expect(not bool(survivor.call("try_gather", "wood", 2, 2))
            and int(survivor.call("get_item_count", "wood_t2")) == wood_before,
            "tier-2 gathering requires the tool, even with sufficient skill"):
        return
    if not _expect(bool(survivor.call("craft_recipe", "scavenger_tool"))
            and str(survivor.get("equipped_tool")) == "scavenger_tool",
            "tool crafts and equips using starter resources"):
        return
    dense_wood.call("interact", survivor)
    hard_stone.call("interact", survivor)
    strong_fiber.call("interact", survivor)
    if not _expect(int(survivor.call("get_item_count", "wood_t2")) == 2
            and int(survivor.call("get_item_count", "stone_t2")) == 2
            and int(survivor.call("get_item_count", "fiber_t2")) == 2,
            "trained gatherer with a tool harvests advanced deposits"):
        return

    if not _expect(bool(survivor.call("craft_recipe", "scrap_spear"))
            and str(survivor.get("equipped_weapon")) == "scrap_spear"
            and float(survivor.call("melee_damage")) == 24.0,
            "crafting weapon changes classless combat damage"):
        return
    if not _expect(bool(survivor.call("craft_recipe", "padded_vest"))
            and str(survivor.get("equipped_armor")) == "padded_vest",
            "crafted armor is equipped"):
        return
    if not _expect(bool(survivor.call("craft_recipe", "reinforced_spear"))
            and str(survivor.get("equipped_weapon")) == "reinforced_spear"
            and float(survivor.call("melee_damage")) == 45.0,
            "tier-2 weapon improves damage"):
        return
    if not _expect(not bool(survivor.call("craft_recipe", "reinforced_spear")),
            "failed crafting cannot grant a free duplicate"):
        return
    if not _expect(bool(survivor.call("craft_recipe", "field_bandage")),
            "medical recipe can be crafted"):
        return
    survivor.set("health", 30.0)
    if not _expect(bool(survivor.call("use_bandage", "field_bandage")),
            "crafted bandage is consumed"):
        return
    survivor.call("receive_damage", 20.0)
    if not _expect(is_equal_approx(float(survivor.get("health")), 45.0),
            "equipped padded vest mitigates infected damage"):
        return

    if not _expect(int(infected.call("receive_hit", 15.0)) == 1
            and int(infected.call("receive_hit", 1000.0)) == 2
            and int(infected.call("receive_hit", 10.0)) == 0,
            "infected handles hits, death, and no double kill"):
        return

    for i in range(10):
        await physics_frame
    if not _expect(survivor.global_position.is_finite(),
            "player transform remains finite"):
        return

    game.queue_free()
    await process_frame
    print("PASS: unified survival, loot, tiered gathering, equipment, crafting, damage, infected and physics.")
    quit(0)
