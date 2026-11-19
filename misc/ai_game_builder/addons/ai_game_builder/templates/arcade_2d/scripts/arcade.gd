extends Node2D

## Simple, dependency-free arcade game. Collect 10 green blocks before time runs out.
const GAME_SIZE := Vector2(900.0, 520.0)
const PLAYER_SPEED := 310.0
const WIN_SCORE := 10
const ROUND_SECONDS := 60.0

var _player: ColorRect
var _target: ColorRect
var _hud: Label
var _time_left := ROUND_SECONDS
var _score := 0
var _finished := false


func _ready() -> void:
	_player = ColorRect.new()
	_player.name = "Player"
	_player.color = Color(0.2, 0.55, 1.0)
	_player.size = Vector2(35, 35)
	_player.position = GAME_SIZE * 0.5
	add_child(_player)

	_target = ColorRect.new()
	_target.name = "Collectible"
	_target.color = Color(0.3, 1.0, 0.4)
	_target.size = Vector2(26, 26)
	add_child(_target)
	_move_target()

	_hud = Label.new()
	_hud.name = "HUD"
	_hud.position = Vector2(18, 18)
	add_child(_hud)
	_refresh_hud()


func _process(delta: float) -> void:
	if _finished:
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
	_time_left = maxf(0.0, _time_left - delta)
	var movement := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) -
		float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) -
		float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	if movement != Vector2.ZERO:
		_player.position += movement.normalized() * PLAYER_SPEED * delta
	_player.position = _player.position.clamp(Vector2.ZERO, GAME_SIZE - _player.size)
	if _player.get_rect().intersects(_target.get_rect()):
		_score += 1
		_move_target()
	if _score >= WIN_SCORE or _time_left <= 0.0:
		_finished = true
	_refresh_hud()


func _move_target() -> void:
	_target.position = Vector2(
		randf_range(40.0, GAME_SIZE.x - 40.0),
		randf_range(70.0, GAME_SIZE.y - 40.0)
	)


func _refresh_hud() -> void:
	var text := "Collect green squares! WASD/arrows | Score: %d/%d | Time: %d" % [_score, WIN_SCORE, ceili(_time_left)]
	if _finished:
		text += "\nYou won! Press R to restart." if _score >= WIN_SCORE else "\nTime up! Press R to retry."
	_hud.text = text
