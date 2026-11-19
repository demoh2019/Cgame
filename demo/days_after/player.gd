extends CharacterBody3D
## Small first-person controller using the built-in Cgame/Godot 3D physics.

signal interaction_requested(target: CollisionObject3D)

const WALK_SPEED := 5.5
const SPRINT_SPEED := 8.5
const JUMP_SPEED := 5.0
const MOUSE_SENSITIVITY := 0.0025

var _camera: Camera3D
var _interaction_ray: RayCast3D


func _ready() -> void:
    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.35
    shape.height = 1.8
    collider.shape = shape
    add_child(collider)

    _camera = Camera3D.new()
    _camera.position.y = 0.65
    _camera.current = true
    add_child(_camera)

    _interaction_ray = RayCast3D.new()
    _interaction_ray.target_position = Vector3(0.0, 0.0, -3.25)
    _interaction_ray.collision_mask = 1
    _interaction_ray.enabled = true
    _camera.add_child(_interaction_ray)

    if DisplayServer.get_name() != "headless":
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity += get_gravity() * delta
    elif Input.is_action_just_pressed("jump"):
        velocity.y = JUMP_SPEED

    var input_direction := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
    var movement := (transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()
    var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
    velocity.x = movement.x * speed
    velocity.z = movement.z * speed
    move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        _camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
        _camera.rotation.x = clampf(_camera.rotation.x, -1.45, 1.45)
    elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    elif event.is_action_pressed("toggle_mouse"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
    elif event.is_action_pressed("interact"):
        var target := get_look_target()
        if target != null:
            interaction_requested.emit(target)


func get_look_target() -> CollisionObject3D:
    if _interaction_ray == null:
        return null
    _interaction_ray.force_raycast_update()
    var hit := _interaction_ray.get_collider()
    if hit is CollisionObject3D:
        return hit
    return null
