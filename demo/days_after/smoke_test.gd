extends SceneTree
## Run with a built Cgame editor:
## godot --headless --path demo/days_after --script res://smoke_test.gd

const SurvivalState = preload("res://survival_state.gd")
const Progression = preload("res://progression.gd")


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var stats = SurvivalState.new()
    stats.advance(10.0, true)
    if stats.hunger >= 100.0 or stats.thirst >= 100.0 or stats.stamina >= 100.0:
        _fail("Needs and sprint stamina must drain.")
        return
    if not stats.replenish("water", 1000.0) or stats.thirst != 100.0:
        _fail("Drinking must restore and clamp thirst.")
        return
    if stats.replenish("invalid", 20.0):
        _fail("Unknown supplies must be rejected.")
        return
    stats.hunger = 0.0
    stats.advance(2.0, false)
    if stats.health >= 100.0:
        _fail("Starvation must damage health.")
        return

    # Validate crafting in isolation: costs are atomic, skills gate advanced recipes.
    var crafting = Progression.new()
    var backpack: Dictionary = {"wood": 2, "scrap": 2, "fiber": 3}
    if crafting.craft(backpack, "not_a_recipe"):
        _fail("Invalid recipe must be rejected.")
        return
    if crafting.craft(backpack, "medkit") or backpack["fiber"] != 3:
        _fail("Level-2 medkit must not consume resources at level 1.")
        return
    if not crafting.craft(backpack, "hatchet"):
        _fail("Hatchet must craft from wood and scrap.")
        return
    if int(backpack["wood"]) != 0 or int(backpack["scrap"]) != 0 or int(backpack["hatchet"]) != 1:
        _fail("Hatchet recipe must consume materials exactly once.")
        return
    if crafting.craft(backpack, "hatchet"):
        _fail("Insufficient materials must not yield another hatchet.")
        return
    if not crafting.craft(backpack, "bandage"):
        _fail("Bandage must craft from fiber.")
        return
    if crafting.skill_level("crafting") < 2:
        _fail("Crafting must award level progression.")
        return
    # A bandage plus a hatchet reaches level 2; a medkit is then attainable
    # with the six fiber/scrap node charges available on the starter map.
    backpack["fiber"] = 3
    backpack["scrap"] = 1
    if not crafting.craft(backpack, "medkit"):
        _fail("Level-2 medkit must be craftable with sufficient materials.")
        return
    if int(backpack["fiber"]) != 0 or int(backpack["scrap"]) != 0 or int(backpack["medkit"]) != 1:
        _fail("Medkit must consume all inputs and create one item.")
        return

    var packed := load("res://main.tscn") as PackedScene
    if packed == null:
        _fail("Cannot load the Days After scene.")
        return
    var level := packed.instantiate()
    root.add_child(level)
    await process_frame
    var player = level.get_node_or_null("Player")
    var supplies := get_nodes_in_group("days_after_supplies")
    if player == null or supplies.size() != 4:
        _fail("Expected player and four resource pickups.")
        return
    var pickup: Node = supplies[0]
    var kind: String = pickup.get("kind")
    var amount: int = pickup.get("amount")
    pickup.call("collect", player)
    await process_frame
    if int(player.inventory[kind]) != amount or is_instance_valid(pickup):
        _fail("Pickup must transfer items exactly once and disappear.")
        return
    var resource_nodes := get_nodes_in_group("days_after_resources")
    if resource_nodes.size() != 6:
        _fail("Expected six gathering nodes.")
        return
    var resource: Node = resource_nodes[0]
    var resource_kind: String = str(resource.get("kind"))
    var charges: int = int(resource.get("remaining"))
    var before_count: int = int(player.inventory[resource_kind])
    var before_xp: int = int(player.progression.experience["gathering"])
    for i in range(charges):
        resource.call("collect", player)
    if int(player.inventory[resource_kind]) != before_count + charges:
        _fail("Gathering must transfer one item per node charge.")
        return
    if int(player.progression.experience["gathering"]) != before_xp + 12 * charges:
        _fail("Gathering must award experience.")
        return
    await process_frame
    if is_instance_valid(resource):
        _fail("Exhausted resource node must disappear.")
        return
    player.add_supply("hatchet", 1)
    if player.gathering_yield("wood", 1) != 2 or player.gathering_yield("scrap", 1) != 1:
        _fail("Hatchet must improve wood gathering only.")
        return
    player.state.health = 50.0
    player.add_supply("bandage", 1)
    if not player.use_medical("bandage") or player.state.health != 75.0:
        _fail("Bandage must heal and be consumed.")
        return
    player.state.hunger = 50.0
    player.add_supply("food", 1)
    if not player.consume("food") or player.state.hunger <= 50.0:
        _fail("Food consumption must restore hunger.")
        return
    level.queue_free()
    await process_frame
    print("PASS: survival, world, loot, gathering, crafting, equipment and progression.")
    quit(0)


func _fail(message: String) -> void:
    push_error("Days After smoke test: " + message)
    quit(1)
