extends SceneTree
## Run with:
## godot --headless --path demo/physics_lab --script res://smoke_test.gd

func _initialize() -> void:
    call_deferred("_check_both_labs")


func _check_both_labs() -> void:
    var checks := [
        {
            "scene": "res://lab_3d.tscn",
            "nodes": ["Ground", "ThinTarget", "DeformableMesh", "SuspensionVehicle", "BodyEnterSensor", "DownwardQuery", "DownwardShapeCast", "HingeBase", "SliderBase", "Environment3D/WaterVolume3D", "Environment3D/MagnetCore", "Environment3D/InteractionHUD3D"],
            "group": "demo_dynamic",
            "minimum": 25
        },
        {
            "scene": "res://lab_2d.tscn",
            "nodes": ["2D Ground", "Thin CCD Target", "AutonomousCharacterBody2D", "UpwardGravityZone", "ThinWallShapeCast", "GrooveSupport", "Environment2D/WaterVolume2D", "Environment2D/Magnet2D", "Environment2D/InteractionHUD2D"],
            "group": "demo_dynamic_2d",
            "minimum": 25
        }
    ]
    var successful := true
    for check in checks:
        var packed := load(check["scene"]) as PackedScene
        if packed == null:
            push_error("Failed to load " + check["scene"])
            successful = false
            continue
        var lab := packed.instantiate()
        root.add_child(lab)
        for frame in range(20):
            await physics_frame
        for node_name in check["nodes"]:
            if lab.get_node_or_null(node_name) == null:
                push_error("%s missing node %s" % [check["scene"], node_name])
                successful = false
        var count := get_nodes_in_group(check["group"]).size()
        # Also exercise newly exposed physics interactions (no UI required).
        var controller_name := "Environment3D" if check["group"] == "demo_dynamic" else "Environment2D"
        var controller: Node = lab.get_node(controller_name)
        if controller_name == "Environment3D":
            controller.call("spawn_water_object", false)
        else:
            controller.call("spawn_water_body", false)
        controller.call("_toggle_wind")
        controller.call("_toggle_magnet")
        controller.call("_cycle_gravity")
        for extra_frame in range(20):
            await physics_frame
        var spawned_count := get_nodes_in_group(check["group"]).size()
        if spawned_count < count + 1:
            push_error("%s failed to spawn an interactive physics body" % check["scene"])
            successful = false
        if count < check["minimum"]:
            push_error("%s has only %d dynamic bodies" % [check["scene"], count])
            successful = false
        print("%s: %d dynamic bodies; %d after interactions" % [check["scene"], count, spawned_count])
        lab.queue_free()
        await process_frame
    if successful:
        print("PASS: both Cgame physics labs and interaction controllers loaded, spawned bodies, and ran 40 physics frames.")
    quit(0 if successful else 1)
