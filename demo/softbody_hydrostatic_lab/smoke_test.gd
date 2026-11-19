extends SceneTree
## Run using the compiled Cgame editor:
## godot --headless --path demo/softbody_hydrostatic_lab --script res://smoke_test.gd


func _initialize() -> void:
    var expected := {
        "physics/3d/physics_engine": "GodotPhysics3D",
        "physics/3d/fluid_plane/enabled": true,
        "physics/3d/solver/soft_body_hydrostatic_pressure": true,
        "physics/3d/solver/soft_body_hydrodynamic_drag": true
    }
    for key in expected:
        if ProjectSettings.get_setting(key, null) != expected[key]:
            push_error("Hydrostatic demo setting %s must be %s" % [key, str(expected[key])])
            quit(1)
            return
    call_deferred("_smoke")


func _smoke() -> void:
    var packed := load("res://main.tscn") as PackedScene
    if packed == null:
        push_error("Unable to load hydrostatic lab main.tscn")
        quit(1)
        return
    var lab := packed.instantiate()
    root.add_child(lab)
    var good := true
    for path in [
        "LightFloatingSoftBody",
        "HeavySinkingSoftBody",
        "OpenClothInCurrent",
        "PoolBottom",
        "WaterVolumeVisual",
        "Camera"
    ]:
        if lab.get_node_or_null(path) == null:
            push_error("Hydrostatic lab missing: " + path)
            good = false
    for body_name in ["LightFloatingSoftBody", "HeavySinkingSoftBody", "OpenClothInCurrent"]:
        var body := lab.get_node_or_null(body_name) as SoftBody3D
        if body == null or body.mesh == null:
            push_error("Invalid closed deformable hull: " + body_name)
            good = false
    for frame in range(120):
        await physics_frame
    lab.queue_free()
    await process_frame
    if good:
        print("PASS: hydrostatic and hydrodynamic settings, two closed hulls and one open cloth across 120 frames")
    quit(0 if good else 1)
