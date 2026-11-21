extends Camera3D
class_name VisualLabFlyCamera3D
## Minimal fly-through camera for renderer/LOD comparisons; UI remains clickable.

@export_range(1.0, 50.0, 0.5) var fly_speed: float = 9.0
@export_range(1.0, 5.0, 0.1) var sprint_multiplier: float = 2.5
@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.003


func _process(delta: float) -> void:
	if not is_current() or delta <= 0.0:
		return
	var direction: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direction -= global_basis.z
	if Input.is_key_pressed(KEY_S):
		direction += global_basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= global_basis.x
	if Input.is_key_pressed(KEY_D):
		direction += global_basis.x
	if Input.is_key_pressed(KEY_E):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		direction -= Vector3.UP
	var current_speed: float = fly_speed * (sprint_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if direction.length_squared() > 0.0:
		global_position += direction.normalized() * current_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotation.y -= event.relative.x * mouse_sensitivity
		rotation.x = clampf(rotation.x - event.relative.y * mouse_sensitivity, -1.45, 1.45)
