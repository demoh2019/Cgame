extends SceneTree

## Built Cgame only:
## ./bin/godot.macos.editor.$(uname -m) --headless --path demo/rod_curvature_lab --script res://smoke_test.gd

func _initialize() -> void:
    if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "GodotPhysics3D":
        push_error("Rod lab needs native GodotPhysics3D.")
        quit(1)
        return
    if float(ProjectSettings.get_setting("physics/3d/solver/soft_body_xpbd_rod_bend_compliance", 0.0)) <= 0.0:
        push_error("Rod bend compliance must be enabled for the demo smoke test.")
        quit(1)
        return
    if float(ProjectSettings.get_setting("physics/3d/solver/soft_body_xpbd_rod_torsion_compliance", 0.0)) <= 0.0:
        push_error("Rod geometric torsion must be enabled for this smoke test.")
        quit(1)
        return
    call_deferred("_test")


func _test() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("Rod curvature main.tscn could not be loaded.")
        quit(1)
        return
    var lab := scene.instantiate()
    root.add_child(lab)
    var ribbon := lab.get_node_or_null("CurvedRodRibbon") as SoftBody3D
    var ball := lab.get_node_or_null("ImpactBall") as RigidBody3D
    var valid := ribbon != null and ribbon.mesh != null and ball != null
    if not valid:
        push_error("Rod curvature test scene lacks a valid deformable ribbon or impact body.")
        quit(1)
        return
    ball.apply_central_impulse(Vector3(7, 1, 0))
    for i in range(90):
        await physics_frame
    if not ball.global_position.is_finite():
        valid = false
        push_error("Collision probe became nonfinite.")
    lab.queue_free()
    await process_frame
    if valid:
        print("PASS: nonplanar rod bend and geometric torsion lab, 90 physics frames.")
    quit(0 if valid else 1)
