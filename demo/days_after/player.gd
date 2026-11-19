extends CharacterBody3D

## Days After: minimal first-person player built entirely from stock 3D nodes.
## This script intentionally does not depend on experimental Cgame physics APIs.

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 5.0
const GRAVITY := 18.0
const MOUSE_SENSITIVITY := 0.0025

var health: float = 100.0
var hunger: float = 80.0
var thirst: float = 80.0
var food_count: int = 0
var water_count: int = 0

@onready var camera: Camera3D = $Head/Camera3D
@onready var aim_ray: RayCast3D = $Head/Camera3D/AimRay


func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        camera.rotation.x = clampf(
            camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.4, 1.4
        )
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= GRAVITY * delta
    elif Input.is_action_just_pressed("jump"):
        velocity.y = JUMP_VELOCITY

    var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var direction := (global_transform.basis * Vector3(move_input.x, 0.0, move_input.y)).normalized()
    var move_speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
    velocity.x = direction.x * move_speed
    velocity.z = direction.z * move_speed
    move_and_slide()

    hunger = maxf(0.0, hunger - 0.24 * delta)
    thirst = maxf(0.0, thirst - 0.38 * delta)
    if hunger <= 0.0 or thirst <= 0.0:
        health = maxf(0.0, health - 3.0 * delta)

    if Input.is_action_just_pressed("interact"):
        var target := get_aimed_pickup()
        if target != null:
            target.call("interact", self)
    if Input.is_action_just_pressed("consume_food"):
        consume_food()
    if Input.is_action_just_pressed("consume_water"):
        consume_water()


func get_aimed_pickup() -> Node:
    if aim_ray == null:
        return null
    aim_ray.force_raycast_update()
    var target := aim_ray.get_collider() as Node
    if target != null and target.has_method("interact"):
        return target
    return null


func collect_item(item_type: String, quantity: int) -> void:
    if quantity <= 0:
        return
    match item_type:
        "food":
            food_count += quantity
        "water":
            water_count += quantity


func consume_food() -> void:
    if food_count <= 0 or health <= 0.0:
        return
    food_count -= 1
    hunger = minf(100.0, hunger + 35.0)


func consume_water() -> void:
    if water_count <= 0 or health <= 0.0:
        return
    water_count -= 1
    thirst = minf(100.0, thirst + 45.0)
