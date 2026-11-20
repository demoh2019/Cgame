extends SceneTree
## Headless character combat regression (no edits to the player's save file).
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_combat.gd

const Stalker = preload("res://scripts/forest_stalker.gd")
const MAX_FRAMES: int = 360

var damage_total: int = 0
var defeated_id: String = ""


func _initialize() -> void:
    call_deferred("_run")


func _on_attack(amount: int) -> void:
    damage_total += amount


func _on_defeated(id: String) -> void:
    defeated_id = id


func _fail(reason: String) -> void:
    push_error("Forest combat smoke FAILED: " + reason)
    quit(1)


func _run() -> void:
    # Stable static ground for actual CharacterBody3D movement.
    var ground := StaticBody3D.new()
    var ground_collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(50.0, 1.0, 50.0)
    ground_collider.shape = shape
    ground_collider.position.y = -0.5
    ground.add_child(ground_collider)
    root.add_child(ground)

    var player := Node3D.new()
    root.add_child(player)
    player.global_position = Vector3(0.0, 1.0, -5.0)

    var enemy := CharacterBody3D.new()
    enemy.name = "TestStalker"
    enemy.set_script(Stalker)
    root.add_child(enemy)
    enemy.call("configure", "-1:0", player, Vector3(0.0, 1.0, 0.0))
    enemy.connect("attack_landed", _on_attack)
    enemy.connect("defeated", _on_defeated)

    for i in range(10):
        await physics_frame
    if damage_total != 0 or not enemy.call("is_alive"):
        _fail("inactive enemy executed AI or failed to initialize")
        return

    enemy.call("set_encounter_active", true)
    var origin: Vector3 = enemy.global_position
    var attacked: bool = false
    for i in range(MAX_FRAMES):
        await physics_frame
        if damage_total > 0:
            attacked = true
            break
    if not attacked:
        _fail("active stalker did not reach and strike its target")
        return
    if enemy.global_position.distance_to(origin) < 1.0:
        _fail("stalker was not moved by physics steering")
        return
    if damage_total != Stalker.ATTACK_DAMAGE:
        _fail("expected a single rate-limited first strike")
        return
    for i in range(15):
        await physics_frame
    if damage_total != Stalker.ATTACK_DAMAGE:
        _fail("enemy attack cooldown did not protect the player")
        return

    if enemy.call("get_health") != Stalker.MAX_HEALTH:
        _fail("enemy max health is incorrect")
        return
    if enemy.call("take_damage", 0) or not enemy.call("take_damage", 1):
        _fail("damage validation and first hit are incorrect")
        return
    if enemy.call("get_health") != 2 or not enemy.call("take_damage", 1):
        _fail("melee damage was not applied")
        return
    if not enemy.call("take_damage", 1) or defeated_id != "-1:0":
        _fail("defeat signal did not report the stable encounter id")
        return
    await process_frame
    if is_instance_valid(enemy):
        _fail("defeated enemy must leave the scene tree")
        return

    print("Forest combat smoke PASSED: dormant AI, CharacterBody chase, attack cooldown, damage and defeat")
    quit(0)
