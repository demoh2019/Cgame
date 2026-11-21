extends SceneTree
## Run: godot --headless --path games/days_after --script res://smoke_test.gd


func _initialize() -> void:
    call_deferred("_smoke")


func _smoke() -> void:
    var ok := true
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("Days After scene cannot be loaded")
        quit(1)
        return
    var game := scene.instantiate()
    root.add_child(game)
    for frame in range(6):
        await physics_frame
    for path in ["Ground", "Survivor/Camera3D/InteractionRay", "HUD/Stats", "HUD/Progression", "InfectedScavenger"]:
        if game.get_node_or_null(path) == null:
            push_error("Missing scene node: " + path)
            ok = false

    var lod: Node = game.get_node_or_null("DebrisLOD")
    if lod == null or lod.get_child_count() != 96:
        push_error("Expected 96 deterministic decorative LOD fragments")
        ok = false
    else:
        var shown: int = int(lod.call("get_visible_count"))
        if shown <= 0 or shown > 18:
            push_error("Visual LOD failed to select a bounded nearby fragment set")
            ok = false
        var survivor: Node3D = game.get_node("Survivor")
        var original_position: Vector3 = survivor.global_position
        survivor.global_position = Vector3(200, 0.15, 200)
        lod.call("force_refresh")
        if int(lod.call("get_visible_count")) != 0:
            push_error("Visual LOD kept fragments outside its hard range")
            ok = false
        survivor.global_position = original_position
        lod.call("force_refresh")
        if int(lod.call("get_visible_count")) <= 0:
            push_error("Visual LOD did not restore nearby fragments")
            ok = false

    var foliage := game.get_node_or_null("FoliageScatter") as MultiMeshInstance3D
    if foliage == null or foliage.multimesh == null:
        push_error("Missing exclusion-aware instanced foliage")
        ok = false
    else:
        var positions: PackedVector3Array = foliage.call("get_selected_positions")
        var centers: PackedVector3Array = foliage.call("get_exclusion_centers")
        var radii: PackedFloat64Array = foliage.call("get_exclusion_radii")
        if positions.size() == 0 or positions.size() > 160 or foliage.multimesh.instance_count != positions.size():
            push_error("PCG foliage did not create a bounded instancing batch")
            ok = false
        for i in range(positions.size()):
            for zone in range(centers.size()):
                if positions[i].distance_squared_to(centers[zone]) <= radii[zone] * radii[zone]:
                    push_error("PCG foliage appeared inside an exclusion sphere")
                    ok = false
                    break
            for previous in range(i):
                if positions[i].distance_squared_to(positions[previous]) < 2.1 * 2.1 - 0.0001:
                    push_error("PCG foliage violated minimum spacing")
                    ok = false
                    break
        if not bool(foliage.call("verify_native_fallback_parity")):
            push_error("Native PCG exclusion filter diverged from GDScript fallback")
            ok = false
        foliage.call("regenerate")
        if positions != foliage.call("get_selected_positions"):
            push_error("PCG foliage placement was not deterministic")
            ok = false

    var state = game.get("state")
    var pickups := get_nodes_in_group("days_after_pickup")
    if pickups.size() < 4:
        push_error("Expected 4 scavenging pickups")
        ok = false
    else:
        var first: Node = pickups[0]
        var kind := str(first.get("resource_type"))
        var amount := int(first.get("amount"))
        game.call("_on_interact", first)
        if int(state.inventory[kind]) != amount:
            push_error("Scavenging did not award item")
            ok = false

    var resources := get_nodes_in_group("days_after_resource")
    if resources.size() < 5:
        push_error("Expected 5 finite gathering nodes")
        ok = false
    else:
        var node: Node = resources[0]
        var kind := str(node.get("resource_type"))
        var charge_before := int(node.get("charges"))
        var stock_before := int(state.inventory[kind])
        game.call("_on_interact", node)
        if int(node.get("charges")) != charge_before - 1 or int(state.inventory[kind]) != stock_before + 1:
            push_error("Resource gathering did not update node and stock")
            ok = false
        if int(state.experience["gathering"]) != 5:
            push_error("Gathering did not grant XP")
            ok = false

    var snapshot: Dictionary = state.inventory.duplicate(true)
    if state.craft("padded_coat") or state.inventory != snapshot:
        push_error("Failed craft was not atomic")
        ok = false

    state.add_resource("wood", 2)
    state.add_resource("scrap", 1)
    var initial_scrap := int(state.inventory["scrap"])
    var bare_damage: float = state.get_attack_damage()
    if not state.craft("makeshift_spear") or not state.equip("makeshift_spear"):
        push_error("Cannot craft and equip spear")
        ok = false
    if state.get_attack_damage() <= bare_damage or int(state.inventory["scrap"]) != initial_scrap - 1:
        push_error("Spear stats or material consumption incorrect")
        ok = false

    state.add_resource("fiber", 3)
    state.add_resource("scrap", 2)
    if not state.craft("padded_coat") or not state.equip("padded_coat"):
        push_error("Cannot craft and equip coat")
        ok = false
    var hp_before: float = state.health
    game.call("_on_enemy_attack", 20.0)
    if absf(state.health - (hp_before - 15.0)) > 0.01:
        push_error("Coat did not reduce damage by 25 percent")
        ok = false

    state.add_resource("fiber", 2)
    if not state.craft("bandage"):
        push_error("Cannot craft bandage")
        ok = false
    var wounded_hp: float = state.health
    if not state.use_resource("bandage") or state.health <= wounded_hp:
        push_error("Bandage did not heal")
        ok = false
    if state.skill_level("crafting") <= 1:
        push_error("Crafting XP did not improve level")
        ok = false

    var enemies := get_nodes_in_group("days_after_enemy")
    if enemies.size() != 1:
        push_error("Expected one infected target")
        ok = false
    else:
        var infected: Node = enemies[0]
        var infected_hp := float(infected.get("health"))
        game.call("_on_attack", infected)
        if float(infected.get("health")) >= infected_hp:
            push_error("Attack did not damage infected")
            ok = false

    state.hunger = 0.01
    state.thirst = 0.01
    var health_before: float = state.health
    state.tick(1.0, true)
    if state.health >= health_before or state.stamina >= 100.0:
        push_error("Survival and sprinting did not advance")
        ok = false

    game.queue_free()
    await process_frame
    if ok:
        print("PASS: scene, bounded visual LOD, exclusion-safe PCG foliage, scavenging, gathering, XP, crafting, gear, combat and survival")
    quit(0 if ok else 1)
