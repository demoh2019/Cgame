extends CharacterBody2D
## Lightweight PvE enemy with a safe-camp exclusion radius.

var game = null
var target: CharacterBody2D
var hp: int = 40
var bite_cooldown: float = 0.0

const AGGRO_RANGE: float = 390.0
const WALK_SPEED: float = 73.0


func _ready() -> void:
	var hitbox := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 11.0
	hitbox.shape = circle
	add_child(hitbox)
	collision_layer = 2
	collision_mask = 0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	bite_cooldown = maxf(0.0, bite_cooldown - delta)
	var distance: float = global_position.distance_to(target.global_position)
	if game.is_safe_at(global_position):
		velocity = Vector2.ZERO
	elif distance < AGGRO_RANGE and not game.is_safe_at(target.global_position):
		velocity = global_position.direction_to(target.global_position) * WALK_SPEED
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	position = position.clamp(Vector2(14, 14), game.map_size - Vector2(14, 14))
	if distance < 26.0 and bite_cooldown <= 0.0 and not game.is_safe_at(target.global_position):
		bite_cooldown = 1.1
		game.apply_player_damage(9.0)


func take_hit(amount: int) -> void:
	hp -= amount
	queue_redraw()
	if hp <= 0:
		game.infected_defeated(global_position)
		queue_free()


func _draw() -> void:
	draw_circle(Vector2(0, 3), 14, Color(0.10, 0.03, 0.04, 0.5))
	draw_circle(Vector2.ZERO, 11, Color(0.64, 0.23, 0.24))
	draw_circle(Vector2(-3, -2), 2, Color(0.94, 0.84, 0.62))
	draw_circle(Vector2(3, -2), 2, Color(0.94, 0.84, 0.62))
	draw_arc(Vector2.ZERO, 13, 0, TAU, 20, Color(0.7, 0.1, 0.08, 0.8), 1.3)
