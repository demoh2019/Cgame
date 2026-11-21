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
        var weighted: PackedInt32Array = foliage.call("get_selected_variants")
        var stable_ids: PackedInt64Array = foliage.call("get_selected_stable_ids")
        if weighted.size() != positions.size() or stable_ids.size() != positions.size():
            push_error("Native PCG weighted variants lost decorative point identities")
            ok = false
        if not foliage.multimesh.use_colors:
            push_error("Weighted foliage variants lost per-instance colors")
            ok = false
        if foliage.get_child_count() != 5:
            push_error("Expected five persistent extra LOD/mesh instancing batches, not per-plant nodes")
            ok = false
        if not bool(foliage.call("verify_variant_partition_native_fallback_parity")):
            push_error("Native variant mesh buckets disagree with GDScript fallback")
            ok = false
        if not bool(foliage.call("verify_variant_native_fallback_parity")):
            push_error("Weighted PCG variant selection diverged from stock Godot fallback")
            ok = false
        var variant_counts: PackedInt32Array = foliage.call("get_variant_counts")
        if variant_counts.size() != 3 or variant_counts[0] <= 0 or \
                variant_counts[1] <= 0 or variant_counts[2] <= 0:
            push_error("Weighted native plant variants were not all represented")
            ok = false
        if variant_counts.size() == 3 and variant_counts[0] + \
                variant_counts[1] + variant_counts[2] != positions.size():
            push_error("Weighted native variant counts did not cover the MultiMesh")
            ok = false
        var packed_counts: PackedInt32Array = foliage.call("get_variant_batch_sizes")
        if packed_counts != variant_counts:
            push_error("Per-geometry native PCG instance buckets disagree with visual variants")
            ok = false
        var lod_tiers: PackedInt32Array = foliage.call("get_lod_tiers")
        var lod_counts: PackedInt32Array = foliage.call("get_lod_batch_sizes")
        if lod_tiers.size() != positions.size() or lod_counts.size() != 6:
            push_error("Two-level PCG geometry LOD is not fully initialized")
            ok = false
        if not bool(foliage.call("verify_lod_native_fallback_parity")):
            push_error("Native LOD hysteresis and mesh bucketing disagreed with GDScript")
            ok = false
        var nearby_lod: int = 0
        var distant_lod: int = 0
        for tier in lod_tiers:
            if tier == 0:
                nearby_lod += 1
            elif tier == 1:
                distant_lod += 1
            else:
                push_error("Invalid per-instance mesh LOD tier")
                ok = false
        if nearby_lod <= 0 or distant_lod <= 0:
            push_error("Foliage demo did not exercise both near and far geometry LOD")
            ok = false
        var source_visits := PackedInt32Array()
        source_visits.resize(positions.size())
        var child_renderer_ids := PackedInt64Array()
        for variant in 3:
            for lod in 2:
                var renderer := foliage.call(
                    "get_lod_renderer", variant, lod) as MultiMeshInstance3D
                if renderer == null or renderer.multimesh == null or renderer.multimesh.mesh == null:
                    push_error("Missing instanced PCG variant %d LOD%d" % [variant, lod])
                    ok = false
                    continue
                if not renderer.multimesh.use_colors:
                    push_error("PCG LOD mesh batch lost per-instance colors")
                    ok = false
                if lod == 1 and not (renderer.multimesh.mesh is QuadMesh):
                    push_error("Far procedural foliage must use a two-triangle quad proxy")
                    ok = false
                if lod == 0:
                    if variant == 0 and not (renderer.multimesh.mesh is BoxMesh):
                        push_error("Green foliage detailed LOD must use box blades")
                        ok = false
                    elif variant == 1 and not (renderer.multimesh.mesh is CylinderMesh):
                        push_error("Autumn foliage detailed LOD must use tapered reeds")
                        ok = false
                    elif variant == 2 and not (renderer.multimesh.mesh is SphereMesh):
                        push_error("Dry foliage detailed LOD must use seed heads")
                        ok = false
                if variant > 0 or lod > 0:
                    child_renderer_ids.push_back(renderer.get_instance_id())
                var source_indices: PackedInt32Array = foliage.call(
                    "get_lod_source_indices", variant, lod)
                if source_indices.size() != renderer.multimesh.instance_count:
                    push_error("PCG LOD batch lost instances or source index mapping")
                    ok = false
                    continue
                for local_index in source_indices.size():
                    var source_index: int = source_indices[local_index]
                    if source_index < 0 or source_index >= weighted.size():
                        push_error("PCG LOD batch contained invalid original source index")
                        ok = false
                        continue
                    source_visits[source_index] += 1
                    if weighted[source_index] != variant or lod_tiers[source_index] != lod:
                        push_error("Per-instance geometry LOD reassigned a variant or tier")
                        ok = false
                    if renderer.multimesh.get_instance_transform(local_index).origin.distance_to(
                            positions[source_index]) > 0.0001:
                        push_error("Foliage LOD moved a plant from its PCG-generated position")
                        ok = false
                    if renderer.multimesh.get_instance_color(local_index).a < 0.99:
                        push_error("Foliage LOD lost its per-plant color")
                        ok = false
        for visits in source_visits:
            if visits != 1:
                push_error("PCG mesh grouping duplicated or dropped an instance")
                ok = false
                break
        var centers: PackedVector3Array = foliage.call("get_exclusion_centers")
        var radii: PackedFloat64Array = foliage.call("get_exclusion_radii")
        var box_mins: PackedVector3Array = foliage.call("get_exclusion_box_mins")
        var box_maxs: PackedVector3Array = foliage.call("get_exclusion_box_maxs")
        var obb_centers: PackedVector3Array = foliage.call("get_oriented_box_centers")
        var obb_halves: PackedVector3Array = foliage.call("get_oriented_box_half_extents")
        var obb_yaws: PackedFloat64Array = foliage.call("get_oriented_box_yaws")
        var fence := game.get_node_or_null("DiagonalFence") as StaticBody3D
        if fence == null or obb_centers.size() != 1 or obb_halves.size() != 1 or obb_yaws.size() != 1:
            push_error("Rotated PCG exclusion or its physical fence is missing")
            ok = false
        else:
            if fence.position.distance_to(obb_centers[0]) > 0.0001 or \
                    absf(fence.rotation.y - obb_yaws[0]) > 0.0001:
                push_error("Rotated PCG exclusion does not match the actual solid geometry")
                ok = false
        if int(foliage.call("get_oriented_box_only_candidate_count")) < 1:
            push_error("Oriented volume does not exclude additional foliage outside existing spheres/AABBs")
            ok = false
        if box_mins.size() != 6 or box_mins.size() != box_maxs.size():
            push_error("PCG rectangle exclusion zone configuration is incomplete")
            ok = false
        if int(foliage.call("get_box_only_candidate_count")) < 1:
            push_error("Rectangular exclusion volumes are not covering any additional grass candidates")
            ok = false
        var trail: PackedVector3Array = foliage.call("get_trail_points")
        var trail_factors: PackedFloat32Array = foliage.call("get_trail_factors")
        if trail.size() != 5 or trail_factors.size() != 625:
            push_error("PCG native trail falloff mask is missing or has invalid dimensions")
            ok = false
        else:
            var cleared: int = 0
            var transition: int = 0
            var untouched: int = 0
            for factor in trail_factors:
                if factor < -0.00001 or factor > 1.00001:
                    push_error("PCG trail mask generated a factor outside [0,1]")
                    ok = false
                elif factor == 0.0:
                    cleared += 1
                elif factor < 1.0:
                    transition += 1
                else:
                    untouched += 1
            if cleared < 20 or transition < 40 or untouched < 250:
                push_error("PCG trail did not create a cleared path and smooth biome transition")
                ok = false
        if not bool(foliage.call("verify_trail_native_fallback_parity")):
            push_error("Native PCG path falloff disagrees with GDScript reference")
            ok = false
        var sampled_foliage_factors: PackedFloat32Array = foliage.call("_sample_trail_fallback", positions)
        for factor in sampled_foliage_factors:
            if factor <= 0.0:
                push_error("PCG grass was placed in the fully cleared trail corridor")
                ok = false
                break
        var densities: PackedFloat32Array = foliage.call("get_density_values")
        var sampled_count: int = int(foliage.call("get_density_sampled_count"))
        if densities.size() != 625 or sampled_count < 250 or sampled_count > 500:
            push_error("PCG seeded per-ID density sampling has an invalid candidate population")
            ok = false
        else:
            var low_density: int = 0
            var high_density: int = 0
            for density in densities:
                if density < 0.2:
                    low_density += 1
                if density > 0.9:
                    high_density += 1
            if low_density < 50 or high_density < 100:
                push_error("PCG biome density regions were not generated")
                ok = false
        if positions.size() == 0 or positions.size() > 160 or \
                int(foliage.call("get_rendered_instance_count")) != positions.size():
            push_error("PCG foliage did not create a bounded instancing batch")
            ok = false
        for i in range(positions.size()):
            for zone in range(centers.size()):
                if positions[i].distance_squared_to(centers[zone]) <= radii[zone] * radii[zone]:
                    push_error("PCG foliage appeared inside an exclusion sphere")
                    ok = false
                    break
            for box_index in range(box_mins.size()):
                var lo: Vector3 = box_mins[box_index]
                var hi: Vector3 = box_maxs[box_index]
                var point: Vector3 = positions[i]
                if point.x >= lo.x and point.x <= hi.x and point.y >= lo.y and point.y <= hi.y and point.z >= lo.z and point.z <= hi.z:
                    push_error("PCG foliage appeared inside an inclusive rectangular exclusion volume")
                    ok = false
                    break
            # Independent geometric check, using the engine Basis inverse
            # instead of the gameplay helper's hand-written yaw projection.
            for b in range(mini(obb_centers.size(), mini(obb_halves.size(), obb_yaws.size()))):
                var local_point: Vector3 = Basis(Vector3.UP, obb_yaws[b]).inverse() * (
                    positions[i] - obb_centers[b])
                if absf(local_point.x) <= obb_halves[b].x and \
                        absf(local_point.y) <= obb_halves[b].y and \
                        absf(local_point.z) <= obb_halves[b].z:
                    push_error("PCG foliage appeared inside a rotated exclusion box")
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
        # Forced far-view test must move all instances into low triangle
        # proxies, then an authored regeneration must recover the initial
        # near/far split without moving or re-rolling any original plant.
        if not bool(foliage.call("force_lod_refresh", Vector3(300.0, 0.15, 300.0))):
            push_error("Foliage LOD did not accept a far-away viewer")
            ok = false
        var far_view_tiers: PackedInt32Array = foliage.call("get_lod_tiers")
        for tier in far_view_tiers:
            if tier != 1:
                push_error("Far-view LOD retained detailed plant geometry")
                ok = false
                break
        if int(foliage.call("get_rendered_instance_count")) != positions.size():
            push_error("Far-view LOD dropped or duplicated visible plants")
            ok = false
        if not bool(foliage.call("verify_lod_native_fallback_parity")):
            push_error("Native LOD hysteresis diverged after changing camera distance")
            ok = false
        foliage.call("regenerate")
        if lod_tiers != foliage.call("get_lod_tiers"):
            push_error("Foliage regeneration did not restore authored near/far LOD")
            ok = false
        if positions != foliage.call("get_selected_positions"):
            push_error("PCG foliage placement was not deterministic")
            ok = false
        if weighted != foliage.call("get_selected_variants") or \
                stable_ids != foliage.call("get_selected_stable_ids"):
            push_error("PCG weighted visual variants changed after regeneration")
            ok = false
        if int(foliage.call("get_rendered_instance_count")) != positions.size() or \
                foliage.call("get_variant_batch_sizes") != packed_counts or \
                foliage.get_child_count() != 5:
            push_error("PCG mesh batching duplicated or lost instances during regeneration")
            ok = false
        var child_index: int = 0
        for variant in 3:
            for lod in 2:
                if variant == 0 and lod == 0:
                    continue
                var renderer_after := foliage.call(
                    "get_lod_renderer", variant, lod) as MultiMeshInstance3D
                if renderer_after == null or child_index >= child_renderer_ids.size() or \
                        renderer_after.get_instance_id() != child_renderer_ids[child_index]:
                    push_error("LOD regeneration allocated new mesh nodes instead of reusing them")
                    ok = false
                child_index += 1

    var trail := game.get_node_or_null("TrailMarkers") as MultiMeshInstance3D
    if trail == null or trail.multimesh == null:
        push_error("Missing native-sampled instanced trail stones")
        ok = false
    else:
        var raw_stones: PackedVector3Array = trail.call("get_raw_samples")
        var kept_stones: PackedVector3Array = trail.call("get_selected_positions")
        var route: PackedVector3Array = trail.call("get_path_points")
        if raw_stones.size() < 20 or raw_stones.size() > 192:
            push_error("PCG polyline sampler failed to create a bounded visible route")
            ok = false
        elif (raw_stones[0].distance_to(route[0]) > 0.001
                or raw_stones[raw_stones.size() - 1].distance_to(route[route.size() - 1]) > 0.001):
            push_error("PCG fitted route did not include both endpoints")
            ok = false
        for i in range(1, raw_stones.size()):
            if raw_stones[i].distance_to(raw_stones[i - 1]) > 1.351:
                push_error("PCG polyline samples exceeded maximum arc spacing")
                ok = false
                break
        if kept_stones.size() < 12 or kept_stones.size() > raw_stones.size():
            push_error("PCG trail structure filtering removed the route")
            ok = false
        if trail.multimesh.instance_count != kept_stones.size():
            push_error("PCG trail MultiMesh count does not match sampled positions")
            ok = false
        var trail_box_mins: PackedVector3Array = foliage.call("get_exclusion_box_mins")
        var trail_box_maxs: PackedVector3Array = foliage.call("get_exclusion_box_maxs")
        for stone in kept_stones:
            for box_index in range(trail_box_mins.size()):
                var lo: Vector3 = trail_box_mins[box_index]
                var hi: Vector3 = trail_box_maxs[box_index]
                if (stone.x >= lo.x - 0.5 and stone.x <= hi.x + 0.5
                        and stone.y >= lo.y and stone.y <= hi.y
                        and stone.z >= lo.z - 0.5 and stone.z <= hi.z + 0.5):
                    push_error("PCG trail stones intersected a structural exclusion volume")
                    ok = false
                    break
        if not bool(trail.call("verify_native_fallback_parity")):
            push_error("Native PCG route sampling disagrees with the GDScript reference")
            ok = false
        trail.call("regenerate")
        if (raw_stones != trail.call("get_raw_samples")
                or kept_stones != trail.call("get_selected_positions")):
            push_error("PCG trail route was not deterministic after regeneration")
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
        print("PASS: scene, bounded visual LOD, exclusion-safe PCG foliage, path-density falloff, scavenging, gathering, XP, crafting, gear, combat and survival")
    quit(0 if ok else 1)
