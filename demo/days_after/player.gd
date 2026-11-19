extends CharacterBody3D
## Minimal first-person survival controller; gameplay logic is in survival_state.gd.

const SurvivalState = preload("res://survival_state.gd")
const Progression = preload("res://progression.gd")
const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.2
const JUMP_VELOCITY := 4.6
const MOUSE_SENSITIVITY := 0.0025
const INTERACTION_RANGE := 3.0

var state = SurvivalState.new()
var inventory: Dictionary = {
    "food": 0, "water": 0, "wood": 0, "fiber": 0, "scrap": 0,
    "bandage": 0, "hatchet": 0, "medkit": 0
}
var progression = Progression.new()
var _camera: Camera3D
var _target: Node
var _gravity := 9.8


func _ready() -> void:
    name = "Player"
    floor_snap_length = 0.15
    _gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.35
    capsule.height = 1.7
    var collider := CollisionShape3D.new()
    collider.shape = capsule
    add_child(collider)

    _camera = Camera3D.new()
    _camera.name = "ViewCamera"
    _camera.position = Vector3(0.0, 0.65, 0.0)
    _camera.current = true
    add_child(_camera)
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        _camera.rotation.x = clampf(_camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.4, 1.4)
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    elif event is InputEventKey and event.pressed and not event.echo:
        match event.physical_keycode:
            KEY_ESCAPE:
                Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
            KEY_E:
                try_interact()
            KEY_1:
                consume("food")
            KEY_2:
                consume("water")
            KEY_3:
                use_medical("bandage")
            KEY_4:
                craft_item("bandage")
            KEY_5:
                craft_item("hatchet")
            KEY_6:
                craft_item("medkit")
            KEY_7:
                use_medical("medkit")
            KEY_SPACE:
                if is_on_floor():
                    velocity.y = JUMP_VELOCITY


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= _gravity * delta
    elif velocity.y < 0.0:
        velocity.y = 0.0

    var x := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
    var z := (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0)
    var input_direction := Vector3(x, 0.0, z).normalized()
    var moving := input_direction.length_squared() > 0.0
    var sprinting := moving and state.stamina > 0.0 and Input.is_key_pressed(KEY_SHIFT)
    var direction := global_transform.basis * input_direction
    var speed := SPRINT_SPEED if sprinting else WALK_SPEED
    velocity.x = direction.x * speed
    velocity.z = direction.z * speed
    if state.health <= 0.0:
        velocity.x = 0.0
        velocity.z = 0.0
        sprinting = false
    move_and_slide()
    state.advance(delta, sprinting)
    _target = _find_target()


func _find_target() -> Node:
    var start := _camera.global_position
    var end := start - _camera.global_transform.basis.z * INTERACTION_RANGE
    var query := PhysicsRayQueryParameters3D.create(start, end)
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    var candidate = hit.get("collider")
    if candidate is Node and candidate.has_method("collect"):
        return candidate
    return null


func try_interact() -> void:
    if _target != null and is_instance_valid(_target):
        _target.call("collect", self)
        _target = null


func target_caption() -> String:
    if _target != null and is_instance_valid(_target):
        return str(_target.get("caption"))
    return ""


func add_supply(kind: String, amount: int) -> bool:
    if amount <= 0 or not inventory.has(kind):
        return false
    inventory[kind] = int(inventory[kind]) + amount
    return true


func consume(kind: String) -> bool:
    if int(inventory.get(kind, 0)) <= 0:
        return false
    var restored := false
    if kind == "food" and state.hunger < SurvivalState.MAX_VALUE:
        restored = state.replenish("food", 32.0)
    elif kind == "water" and state.thirst < SurvivalState.MAX_VALUE:
        restored = state.replenish("water", 40.0)
    if restored:
        inventory[kind] = int(inventory[kind]) - 1
    return restored


func award_gathering(points: int) -> void:
    progression.gain_experience("gathering", points)


func gathering_yield(kind: String, base_amount: int) -> int:
    if kind == "wood" and int(inventory.get("hatchet", 0)) > 0:
        return base_amount + 1
    return base_amount


func craft_item(recipe_id: String) -> bool:
    return progression.craft(inventory, recipe_id)


func use_medical(kind: String) -> bool:
    if state.health >= SurvivalState.MAX_VALUE or int(inventory.get(kind, 0)) <= 0:
        return false
    var restored := 0.0
    if kind == "bandage":
        restored = 25.0
    elif kind == "medkit":
        restored = 65.0
    if restored <= 0.0:
        return false
    inventory[kind] = int(inventory[kind]) - 1
    state.health = minf(SurvivalState.MAX_VALUE, state.health + restored)
    return true
