extends CharacterBody3D
## Controllable survivor with stamina, hunger, thirst and a small inventory.

signal attacked(damage: float, reach: float)
signal died

const WALK_SPEED := 5.0
const RUN_SPEED := 8.0
const GRAVITY := 24.0

var health := 100.0
var hunger := 100.0
var thirst := 100.0
var stamina := 100.0
var dead := false
var inventory: Dictionary = {"food": 1, "water": 1, "scrap": 0}
var attack_cooldown := 0.0


func _ready() -> void:
    name = "Player"
    collision_layer = 2
    collision_mask = 1
    add_to_group("survivor")

    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.37
    capsule.height = 1.8
    var collision := CollisionShape3D.new()
    collision.shape = capsule
    collision.position.y = 0.9
    add_child(collision)

    var body := MeshInstance3D.new()
    var mesh := CapsuleMesh.new()
    mesh.radius = 0.37
    mesh.height = 1.8
    body.mesh = mesh
    body.position.y = 0.9
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.20, 0.47, 0.76)
    body.material_override = material
    add_child(body)

    var camera := Camera3D.new()
    camera.name = "SurvivorCamera"
    camera.position = Vector3(0.0, 16.0, 12.0)
    camera.rotation_degrees = Vector3(-52.0, 0.0, 0.0)
    camera.current = true
    add_child(camera)


func _physics_process(delta: float) -> void:
    if dead:
        velocity = Vector3.ZERO
        return

    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    hunger = maxf(0.0, hunger - delta * 0.20)
    thirst = maxf(0.0, thirst - delta * 0.32)
    if hunger <= 0.0 or thirst <= 0.0:
        take_damage(delta * 3.0)
        if dead:
            return

    var movement := Vector3.ZERO
    if Input.is_key_pressed(KEY_W):
        movement.z -= 1.0
    if Input.is_key_pressed(KEY_S):
        movement.z += 1.0
    if Input.is_key_pressed(KEY_A):
        movement.x -= 1.0
    if Input.is_key_pressed(KEY_D):
        movement.x += 1.0
    movement = movement.normalized()

    var sprinting: bool = movement.length_squared() > 0.0 and Input.is_key_pressed(KEY_SHIFT) and stamina > 0.0
    var speed: float = RUN_SPEED if sprinting else WALK_SPEED
    if sprinting:
        stamina = maxf(0.0, stamina - delta * 17.0)
    else:
        stamina = minf(100.0, stamina + delta * 10.0)

    velocity.x = movement.x * speed
    velocity.z = movement.z * speed
    if is_on_floor():
        velocity.y = -0.2
    else:
        velocity.y -= GRAVITY * delta
    move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
    if dead:
        return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        perform_attack()
    elif event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_SPACE:
                perform_attack()
            KEY_1:
                consume("food")
            KEY_2:
                consume("water")


func perform_attack() -> void:
    if dead or attack_cooldown > 0.0:
        return
    attack_cooldown = 0.55
    attacked.emit(40.0, 2.7)


func take_damage(amount: float) -> void:
    if dead:
        return
    health = maxf(0.0, health - maxf(0.0, amount))
    if health <= 0.0:
        dead = true
        died.emit()


func add_item(item_type: String, amount: int) -> void:
    if amount <= 0:
        return
    inventory[item_type] = int(inventory.get(item_type, 0)) + amount


func consume(item_type: String) -> bool:
    var count: int = int(inventory.get(item_type, 0))
    if dead or count <= 0:
        return false
    if item_type == "food":
        hunger = minf(100.0, hunger + 35.0)
    elif item_type == "water":
        thirst = minf(100.0, thirst + 45.0)
    else:
        return false
    inventory[item_type] = count - 1
    return true
