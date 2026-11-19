extends CharacterBody3D
## First-person survivor using the engine's CharacterBody3D collision solver.

signal interact_requested(target: Node)
signal attack_requested(target: Node)

const WALK_SPEED: float = 4.3
const SPRINT_SPEED: float = 7.1
const ACCELERATION: float = 15.0
const LOOK_SENSITIVITY: float = 0.0025
const ATTACK_INTERVAL: float = 0.65

var sprint_allowed: bool = true
var is_sprinting: bool = false
var can_move: bool = true
var attack_timer: float = 0.0

@onready var camera: Camera3D = $Camera3D
@onready var interaction_ray: RayCast3D = $Camera3D/InteractionRay


func _ready() -> void:
    interaction_ray.add_exception(self)
    if DisplayServer.get_name() != "headless":
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and can_move:
        rotate_y(-event.relative.x * LOOK_SENSITIVITY)
        camera.rotate_x(-event.relative.y * LOOK_SENSITIVITY)
        camera.rotation.x = clampf(camera.rotation.x, -1.45, 1.45)
    elif event.is_action_pressed("interact") and can_move:
        var target := get_focused_pickup()
        if target != null:
            interact_requested.emit(target)
    elif event.is_action_pressed("attack") and can_move and attack_timer <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        attack_timer = ATTACK_INTERVAL
        interaction_ray.force_raycast_update()
        var hit := interaction_ray.get_collider() as Node
        if hit != null and hit.has_method("take_damage"):
            attack_requested.emit(hit)


func _physics_process(delta: float) -> void:
    attack_timer = maxf(0.0, attack_timer - delta)
    var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    if not can_move:
        input_vector = Vector2.ZERO
    is_sprinting = can_move and sprint_allowed and Input.is_action_pressed("sprint") and input_vector.length_squared() > 0.001
    var direction := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
    var speed := SPRINT_SPEED if is_sprinting else WALK_SPEED
    velocity.x = move_toward(velocity.x, direction.x * speed, ACCELERATION * delta)
    velocity.z = move_toward(velocity.z, direction.z * speed, ACCELERATION * delta)
    if not is_on_floor():
        velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * delta
    else:
        velocity.y = -0.05
    move_and_slide()


func get_focused_pickup() -> Node:
    if not interaction_ray.is_colliding():
        return null
    var target := interaction_ray.get_collider() as Node
    if target != null and target.has_method("collect") and not target.is_queued_for_deletion():
        return target
    return null
