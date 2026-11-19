extends Node3D

## Playable 3D collectathon built entirely from Godot primitives.
## No external assets, input map changes, plugins, network, or API keys needed.

const PLAYER_SPEED := 7.0
const ARENA_RADIUS := 8.0
const ROUND_SECONDS := 90.0
const TARGET_POSITIONS := [
	Vector3(4.0, 0.0, -4.0),
	Vector3(-4.0, 0.0, -3.0),
	Vector3(2.0, 0.0, 4.0),
	Vector3(-5.0, 0.0, 5.0),
	Vector3(5.0, 0.0, 2.0),
	Vector3(0.0, 0.0, -6.0),
]
const WIN_SCORE := 6

var _player: MeshInstance3D
var _target: MeshInstance3D
var _hud: Label
var _elapsed := 0.0
var _score := 0
var _finished := false


func _ready() -> void:
	_make_box("Floor", Color(0.16, 0.23, 0.28), Vector3(19.0, 0.3, 19.0), Vector3(0, -0.3, 0))
	for z in [-9.0, 9.0]:
		_make_box("WallZ", Color(0.3, 0.4, 0.5), Vector3(19.0, 1.0, 0.3), Vector3(0, 0.35, z))
	for x in [-9.0, 9.0]:
		_make_box("WallX", Color(0.3, 0.4, 0.5), Vector3(0.3, 1.0, 19.0), Vector3(x, 0.35, 0))
	_player = _make_box("Player", Color(0.25, 0.6, 1.0), Vector3(0.8, 1.2, 0.8), Vector3(0, 0.6, 0))
	_target = _make_box("Collectible", Color(0.25, 1.0, 0.35), Vector3(0.7, 0.7, 0.7), TARGET_POSITIONS[0] + Vector3.UP * 0.6)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-35), 0)
	add_child(sun)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 17, 17)
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true

	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	add_child(overlay)
	_hud = Label.new()
	_hud.name = "HUD"
	_hud.position = Vector2(20, 20)
	overlay.add_child(_hud)
	_update_hud()


func _process(delta: float) -> void:
	if _finished:
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return

	_elapsed = minf(ROUND_SECONDS, _elapsed + delta)
	var direction := Vector3(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) -
		float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		0,
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) -
		float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	if direction != Vector3.ZERO:
		_player.position += direction.normalized() * PLAYER_SPEED * delta
	_player.position.x = clampf(_player.position.x, -ARENA_RADIUS, ARENA_RADIUS)
	_player.position.z = clampf(_player.position.z, -ARENA_RADIUS, ARENA_RADIUS)

	if _player.position.distance_to(_target.position) < 0.95:
		_score += 1
		if _score < WIN_SCORE:
			_target.position = TARGET_POSITIONS[_score] + Vector3.UP * 0.6
		else:
			_target.visible = false

	_finished = _score >= WIN_SCORE or _elapsed >= ROUND_SECONDS
	_update_hud()


func _make_box(box_name: String, color: Color, dimensions: Vector3, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance


func _update_hud() -> void:
	var remaining := ceili(maxf(0.0, ROUND_SECONDS - _elapsed))
	_hud.text = "3D Arena | WASD / arrows | Targets: %d/%d | Time: %d" % [_score, WIN_SCORE, remaining]
	if _finished:
		_hud.text += "\nYou win! Press R to replay." if _score >= WIN_SCORE else "\nTime over! Press R to retry."
