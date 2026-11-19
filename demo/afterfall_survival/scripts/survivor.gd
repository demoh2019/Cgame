extends CharacterBody2D
## Uses stock Godot CharacterBody2D; engine-specific physics comes later if needed.

var game = null
var active_weapon: String = "club"
var facing: Vector2 = Vector2.RIGHT

const BASE_SPEED: float = 195.0


func _ready() -> void:
	var hitbox := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 13.0
	hitbox.shape = circle
	add_child(hitbox)
	collision_layer = 1
	collision_mask = 0

	var camera := Camera2D.new()
	camera.enabled = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(game.map_size.x)
	camera.limit_bottom = int(game.map_size.y)
	add_child(camera)


func _physics_process(_delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y += 1.0
	if move != Vector2.ZERO:
		facing = move.normalized()
	velocity = move.normalized() * BASE_SPEED * game.get_movement_multiplier()
	move_and_slide()
	position = position.clamp(Vector2(18, 18), game.map_size - Vector2(18, 18))
	if move != Vector2.ZERO:
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(0, 3), 15, Color(0.03, 0.08, 0.08, 0.45))
	draw_circle(Vector2.ZERO, 12, Color(0.26, 0.78, 0.76))
	draw_circle(facing * 8, 4, Color(0.93, 0.95, 0.85))
	draw_line(Vector2.ZERO, facing * (24 if active_weapon == "spear" else 19), Color(0.88, 0.76, 0.46), 4)


func equip(weapon: String) -> void:
	active_weapon = weapon
	queue_redraw()
