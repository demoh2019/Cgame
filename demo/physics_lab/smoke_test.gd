extends SceneTree

# This laboratory deliberately tests the Cgame GodotPhysics3D native solver,
# which is not selected by default when Jolt is included.
## Run with:
## godot --headless --path demo/physics_lab --script res://smoke_test.gd

func _initialize() -> void:
    if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")) != "GodotPhysics3D":
        push_error("Physics Lab must explicitly select GodotPhysics3D to test the Cgame soft-body solver.")
        quit(1)
        return
    call_deferred("_check_both_labs")


func _check_both_labs() -> void:
    var checks := [
        {
            "scene": "res://lab_3d.tscn",
            "nodes": ["Ground", "ThinTarget", "DeformableMesh", "FEMConvexCubeSixTets", "SuspensionVehicle", "BodyEnterSensor", "DownwardQuery", "DownwardShapeCast", "HingeBase", "SliderBase", "Environment3D/WaterVolume3D", "Environment3D/MagnetCore", "Environment3D/InteractionHUD3D", "AdvancedPhysics3D/VortexZone", "AdvancedPhysics3D/ConveyorBelt3D", "AdvancedPhysics3D/LocalGravityWell", "AdvancedPhysics3D/AdvancedHUD3D", "PBFWaterDemo/PBFWaterCPU", "PBFWaterDemo/PBFWaterCPU/ParticleRenderer", "PBFWaterDemo/ReactiveFloat"],
            "group": "demo_dynamic",
            "minimum": 25
        },
        {
            "scene": "res://lab_2d.tscn",
            "nodes": ["2D Ground", "Thin CCD Target", "AutonomousCharacterBody2D", "UpwardGravityZone", "ThinWallShapeCast", "GrooveSupport", "Environment2D/WaterVolume2D", "Environment2D/Magnet2D", "Environment2D/InteractionHUD2D", "AdvancedPhysics2D/VortexField2D", "AdvancedPhysics2D/ConveyorBelt2D", "AdvancedPhysics2D/LocalGravityWell2D", "AdvancedPhysics2D/AdvancedHUD2D"],
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
        # The liquid station must exercise the native PBF class, not a
        # pre-baked mesh or a GDScript-only particle approximation.
        if check["group"] == "demo_dynamic":
            var pbf_fluid := lab.get_node_or_null("PBFWaterDemo/PBFWaterCPU") as PBFParticleFluid3D
            if pbf_fluid == null or pbf_fluid.get_particle_count() != 245:
                push_error("Physics Lab native PBF water tank missing or incorrectly seeded.")
                successful = false
            elif pbf_fluid.collide_with_bodies or pbf_fluid.two_way_rigid_coupling:
                push_error("Physics Lab must leave expensive PBF rigid-body sweeps opt-in.")
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
        var advanced_name := "AdvancedPhysics3D" if check["group"] == "demo_dynamic" else "AdvancedPhysics2D"
        var advanced: Node = lab.get_node(advanced_name)
        var detector_name := "VortexDetector" if advanced_name == "AdvancedPhysics3D" else "VortexDetector2D"
        var detector := advanced.get_node(detector_name)
        var overlap_count := 0
        if detector is Area3D:
            overlap_count = (detector as Area3D).get_overlapping_bodies().size()
        elif detector is Area2D:
            overlap_count = (detector as Area2D).get_overlapping_bodies().size()
        if overlap_count == 0:
            push_error("%s vortex has no physical overlap candidates" % check["scene"])
            successful = false
        advanced.call("_toggle_vortex")
        advanced.call("_toggle_gravity")
        advanced.call("_reverse_belt")
        advanced.call("spawn_fracture_test")
        for extra_frame in range(20):
            await physics_frame
        var spawned_count := get_nodes_in_group(check["group"]).size()
        if spawned_count < count + 3:
            push_error("%s failed to spawn water and fracture physics bodies" % check["scene"])
            successful = false
        if count < check["minimum"]:
            push_error("%s has only %d dynamic bodies" % [check["scene"], count])
            successful = false
        print("%s: %d dynamic bodies; %d after interactions" % [check["scene"], count, spawned_count])
        lab.queue_free()
        await process_frame
    if successful:
        print("PASS: both Cgame physics labs, vortex/belt/gravity/fracture stations and water interactions ran 40 physics frames.")
    quit(0 if successful else 1)
