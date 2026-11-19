extends SceneTree
## Run with:
## godot --headless --path demo/physics_lab --script res://smoke_test.gd

func _initialize() -> void:
    call_deferred("_check_both_labs")


func _check_both_labs() -> void:
    var checks := [
        {
            "scene": "res://lab_3d.tscn",
            "nodes": ["Ground", "ThinTarget", "DeformableMesh", "SuspensionVehicle", "BodyEnterSensor", "DownwardQuery"],
            "group": "demo_dynamic",
            "minimum": 25
        },
        {
            "scene": "res://lab_2d.tscn",
            "nodes": ["2D Ground", "Thin CCD Target", "AutonomousCharacterBody2D", "UpwardGravityZone"],
            "group": "demo_dynamic_2d",
            "minimum": 25
        }
    ]
    var successful := true
    for check in checks:
        var packed: PackedScene = load(check["scene"])
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
        if count < check["minimum"]:
            push_error("%s has only %d dynamic bodies" % [check["scene"], count])
            successful = false
        print("%s: %d dynamic bodies; scene smoke check complete" % [check["scene"], count])
        lab.queue_free()
        await process_frame
    if successful:
        print("PASS: both Cgame physics labs loaded and ran 20 physics frames.")
    quit(0 if successful else 1)
