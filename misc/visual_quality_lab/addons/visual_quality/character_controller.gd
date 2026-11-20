extends CharacterBody3D
class_name VisualLabCharacter3D
## Reusable first-person character for the lab: physics, slopes, air control,
## jumps and optional free-flight. No project-wide InputMap changes.

signal movement_mode_changed(is_flying: bool)

@export_range(1.0, 15.0, 0.5) var walk_speed: float = 5.0
@export_range(1.0, 4.0, 0.1) var sprint_multiplier: float = 1.7
@export_range(1.0, 50.0, 0.5) var ground_acceleration: float = 22.0
@export_range(1.0, 50.0, 0.5) var ground_braking: float = 28.0
@export_range(0.0, 1.0, 0.05) var air_control: float = 0.28
@export_range(1.0, 40.0, 0.5) var gravity: float = 19.0
@export_range(1.0, 15.0, 0.5) var jump_velocity: float = 7.2
@export_range(1.0, 25.0, 0.5) var fly_speed: float = 9.0
@export_range(0.02, 0.30, 0.01) var jump_buffer_seconds: float = 0.12
@export_range(0.02, 0.30, 0.01) var coyote_time_seconds: float = 0.12
@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.003
@export var start_in_fly_mode: bool = false

var is_flying: bool = false
var view_camera: Camera3D
var _jump_buffer_left: float = 0.0
var _coyote_left: float = 0.0
var _jump_was_held: bool = false


func _ready() -> void:
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(45.0)
	_create_capsule_if_missing()
	_create_camera_if_missing()
	if start_in_fly_mode:
		set_fly_mode(true)
	else:
		movement_mode_changed.emit(false)


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var axes: Vector2 = read_movement_axes()
	var direction: Vector3 = global_basis * Vector3(axes.x, 0.0, axes.y)
	var sprinting: bool = Input.is_key_pressed(KEY_SHIFT)
	var jump_held: bool = Input.is_key_pressed(KEY_SPACE)
	if is_flying:
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		_jump_was_held = jump_held
		var vertical: float = (1.0 if Input.is_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_key_pressed(KEY_Q) else 0.0)
		var fly_direction: Vector3 = direction + Vector3.UP * vertical
		velocity = fly_direction.normalized() * fly_speed * (sprint_multiplier if sprinting else 1.0)
		move_and_slide()
		return

	var speed: float = walk_speed * (sprint_multiplier if sprinting else 1.0)
	var desired: Vector3 = direction.normalized() * speed
	var grounded: bool = is_on_floor()
	var acceleration: float = (ground_acceleration if axes.length_squared() > 0.0 else ground_braking)
	if not grounded:
		acceleration *= air_control
	velocity = step_horizontal_velocity(velocity, desired, acceleration, delta)
	# Jump buffering accepts a press shortly before landing; coyote time accepts
	# a press shortly after leaving a ledge. Holding Space does not auto-repeat.
	_jump_buffer_left = maxf(_jump_buffer_left - delta, 0.0)
	if jump_held and not _jump_was_held:
		_jump_buffer_left = jump_buffer_seconds
	_jump_was_held = jump_held
	if grounded:
		_coyote_left = coyote_time_seconds
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)
	if should_jump(_jump_buffer_left, _coyote_left):
		velocity.y = jump_velocity
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
	elif grounded:
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotate_y(-event.relative.x * mouse_sensitivity)
		if is_instance_valid(view_camera):
			view_camera.rotation.x = clampf(view_camera.rotation.x - event.relative.y * mouse_sensitivity, -1.45, 1.45)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		set_fly_mode(not is_flying)
		get_viewport().set_input_as_handled()


func set_fly_mode(enabled: bool) -> void:
	if enabled == is_flying:
		return
	is_flying = enabled
	velocity = Vector3.ZERO
	_coyote_left = 0.0
	_jump_buffer_left = 0.0
	_jump_was_held = Input.is_key_pressed(KEY_SPACE)
	if enabled:
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	else:
		motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	movement_mode_changed.emit(is_flying)


func get_view_camera() -> Camera3D:
	return view_camera


func _create_capsule_if_missing() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			return
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.85
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "PlayerCapsule"
	shape.shape = capsule
	shape.position.y = 0.95
	add_child(shape)


func _create_camera_if_missing() -> void:
	for child in get_children():
		if child is Camera3D:
			view_camera = child
			return
	view_camera = Camera3D.new()
	view_camera.name = "PlayerCamera"
	view_camera.position.y = 1.65
	view_camera.fov = 72.0
	add_child(view_camera)
	view_camera.current = true


## Pure helpers enable regression tests without running physics or a window.
static func read_movement_axes() -> Vector2:
	var x: float = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	var z: float = (1.0 if Input.is_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_key_pressed(KEY_W) else 0.0)
	return Vector2(x, z).normalized()


static func step_horizontal_velocity(current: Vector3, wanted: Vector3, acceleration: float, delta: float) -> Vector3:
	var step: float = maxf(acceleration, 0.0) * maxf(delta, 0.0)
	var from_horizontal: Vector2 = Vector2(current.x, current.z)
	var to_horizontal: Vector2 = Vector2(wanted.x, wanted.z)
	var result: Vector2 = from_horizontal.move_toward(to_horizontal, step)
	return Vector3(result.x, current.y, result.y)


static func should_jump(buffer_left: float, coyote_left: float) -> bool:
	return buffer_left > 0.0 and coyote_left > 0.0
