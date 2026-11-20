extends SceneTree
## Built Cgame:
## --headless --path demo/days_after --script res://smoke_test_weapon_skills.gd

const RULES = preload("res://weapon_skill_rules.gd")

var observed_hits: int = 0
var observed_damage: float = 0.0
var observed_range: float = 0.0


func _initialize() -> void:
    call_deferred("_run")


func _record_attack(damage: float, range_meters: float) -> void:
    observed_hits += 1
    observed_damage = damage
    observed_range = range_meters


func _fail(message: String) -> void:
    push_error("Days After weapon skills: " + message)
    quit(1)


func _run() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        _fail("Cannot load main game")
        return
    var game := scene.instantiate()
    root.add_child(game)
    var survivor := game.get_node_or_null("Player") as CharacterBody3D
    if survivor == null:
        _fail("Player missing")
        return
    survivor.connect("attack_requested", Callable(self, "_record_attack"))
    var infected := game.get_node_or_null("InfectedWalker") as CharacterBody3D
    if infected == null:
        _fail("Combat enemy missing from the playable scene")
        return
    # Put a real infected just outside normal range, but within spear skill range.
    infected.global_position = survivor.global_position - survivor.global_transform.basis.z * 2.9
    var infected_health: float = float(infected.get("health"))
    if not InputMap.has_action("weapon_skill") or not InputMap.has_action("craft_reinforced_spear"):
        _fail("Q or reinforced spear craft action not installed by main game")
        return
    if survivor.call("perform_weapon_skill"):
        _fail("Unarmed player used a weapon skill")
        return
    if observed_hits != 0 or float(survivor.get("combat_energy")) != 100.0:
        _fail("Failed unarmed skill mutated combat state")
        return

    survivor.call("add_item", "rusty_spear", 1)
    if not survivor.call("equip_item", "weapon", "rusty_spear"):
        _fail("Cannot equip crafted spear")
        return
    if not survivor.call("perform_weapon_skill"):
        _fail("Rusty spear skill failed")
        return
    if observed_hits != 1 or not is_equal_approx(observed_damage, 48.0) or not is_equal_approx(observed_range, 3.1):
        _fail("Spear skill damage or reach differs from weapon rule")
        return
    if not is_equal_approx(float(infected.get("health")), infected_health - 48.0):
        _fail("Spear skill signal did not damage an actual infected in range")
        return
    if not is_equal_approx(float(survivor.get("combat_energy")), 75.0):
        _fail("Spear did not spend the specified energy")
        return
    if not is_equal_approx(float(survivor.get("weapon_skill_cooldown")), 6.0):
        _fail("Cooldown not started")
        return
    if survivor.call("perform_weapon_skill") or observed_hits != 1:
        _fail("Skill was spammed during cooldown")
        return

    # Advance simulated time explicitly, without waiting six real seconds.
    survivor.set("attack_cooldown", 0.0)
    survivor.set("weapon_skill_cooldown", 0.0)
    survivor.set("combat_energy", 24.0)
    if survivor.call("perform_weapon_skill") or observed_hits != 1:
        _fail("Insufficient energy should reject the action")
        return
    if not is_equal_approx(float(survivor.get("combat_energy")), 24.0):
        _fail("Failed skill spent energy")
        return

    survivor.call("add_item", "wood_t2", 2)
    survivor.call("add_item", "stone_t2", 2)
    survivor.call("add_item", "fiber_t1", 1)
    if not survivor.call("craft_recipe", "reinforced_spear"):
        _fail("Cannot craft the reinforced spear from gathered tiered materials")
        return
    if int(survivor.call("get_item_count", "wood_t2")) != 0 or int(survivor.call("get_item_count", "stone_t2")) != 0:
        _fail("Reinforced crafting failed to consume both tier 2 resources")
        return
    if str(survivor.get("equipped_weapon")) != "reinforced_spear":
        _fail("Crafted reinforced spear was not auto-equipped")
        return
    survivor.set("combat_energy", 100.0)
    if not survivor.call("perform_weapon_skill"):
        _fail("Reinforced spear skill failed")
        return
    if observed_hits != 2 or not is_equal_approx(observed_damage, 91.0):
        _fail("Reinforced weapon did not change skill damage")
        return
    if not is_equal_approx(observed_range, 3.4):
        _fail("Reinforced weapon did not change reach")
        return
    if not is_equal_approx(float(survivor.get("combat_energy")), 65.0):
        _fail("Wrong reinforced skill energy cost")
        return

    # No ownership: cannot execute a ghost-equipped weapon ability.
    survivor.set("attack_cooldown", 0.0)
    survivor.set("weapon_skill_cooldown", 0.0)
    var empty_inv: Dictionary = {}
    survivor.set("inventory", empty_inv)
    if survivor.call("perform_weapon_skill"):
        _fail("Ghost-equipped weapon gave an active ability")
        return
    survivor.set("health", 0.0)
    survivor.set("combat_energy", 100.0)
    if survivor.call("perform_weapon_skill"):
        _fail("Dead survivor performed an active skill")
        return
    if not is_equal_approx(RULES.damage_for("rusty_spear", 32.0), 48.0):
        _fail("Data-driven skill rule failed")
        return
    if RULES.damage_for("unknown", 32.0) != 0.0:
        _fail("Unknown gear granted skill damage")
        return
    game.queue_free()
    await process_frame
    print("PASS: classless weapon active skills, equipment gates, damage, reach, cooldown and energy.")
    quit(0)
