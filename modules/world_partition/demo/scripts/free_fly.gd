extends Camera3D

@export var move_speed: float = 36.0
@export var sensitivity: float = 0.0025

func _ready() -> void:
    current = true
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * sensitivity)
        rotation.x = clamp(rotation.x - event.relative.y * sensitivity, -1.4, 1.4)
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
    var movement := Vector3(
        float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
        float(Input.is_key_pressed(KEY_SPACE)) - float(Input.is_key_pressed(KEY_CTRL)),
        float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
    )
    if movement.length_squared() > 0.0:
        var speed := move_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
        global_position += global_basis * movement.normalized() * speed * delta
