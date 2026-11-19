extends SceneTree
## Headless: <cgame-editor> --headless --path demo/days_after \
##     --script res://smoke_test_zombie_steering.gd

const Infected = preload("res://zombie.gd")
const TargetProbe = preload("res://test_target_probe.gd")


func _initialize() -> void:
    call_deferred("_run")


func _solid_box(parent: Node3D, name_value: String, at: Vector3, size: Vector3) -> StaticBody3D:
    var obstacle := StaticBody3D.new()
    obstacle.name = name_value
    obstacle.position = at
    var shape := BoxShape3D.new()
    shape.size = size
    var collider := CollisionShape3D.new()
    collider.shape = shape
    obstacle.add_child(collider)
    parent.add_child(obstacle)
    return obstacle


func _fail(message: String) -> void:
    push_error("Zombie steering regression: " + message)
    quit(1)


func _run() -> void:
    var arena := Node3D.new()
    root.add_child(arena)
    _solid_box(arena, "Ground", Vector3(0, -0.5, 0), Vector3(50, 1, 50))
    _solid_box(arena, "Barrier", Vector3(0, 1.2, 0), Vector3(3.0, 2.4, 0.7))

    var survivor := TargetProbe.new()
    survivor.position = Vector3(0, 1.05, -5.0)
    arena.add_child(survivor)

    var infected := Infected.new()
    infected.name = "SteeringInfected"
    infected.target = survivor
    infected.position = Vector3(0, 1.05, 5.0)
    arena.add_child(infected)
    var initial_distance := infected.global_position.distance_to(survivor.global_position)
    for i in range(300):
        await physics_frame

    # A direct-chase controller stays trapped at z > 0 behind this barrier.
    # Local steering should move around its x boundary and reduce the gap.
    var final_distance := infected.global_position.distance_to(survivor.global_position)
    if absf(infected.global_position.x) < 1.4 or final_distance >= initial_distance - 1.0:
        _fail("Infected failed to steer around an obstacle.")
        return
    if not infected.global_position.is_finite():
        _fail("Nonfinite infected position.")
        return

    # Reposition on either side of the barrier within melee range.
    # Without line-of-sight guarding, the original behavior hits through walls.
    infected.global_position = Vector3(0, 1.05, 0.7)
    infected.velocity = Vector3.ZERO
    infected.strike_cooldown = 0.0
    survivor.global_position = Vector3(0, 1.05, -0.7)
    survivor.health = 100.0
    await physics_frame
    await physics_frame
    if survivor.health != 100.0:
        _fail("Infected attacked through a solid barrier.")
        return

    # On the same side, attacks should still be possible.
    survivor.global_position = Vector3(0, 1.05, 1.1)
    infected.strike_cooldown = 0.0
    for i in range(3):
        await physics_frame
    if survivor.health >= 100.0:
        _fail("Unobstructed melee attack did not occur.")
        return

    arena.queue_free()
    await process_frame
    print("PASS: infected local obstacle steering and line-of-sight melee checks.")
    quit(0)
