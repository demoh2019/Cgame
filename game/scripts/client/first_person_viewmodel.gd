extends Node3D
## The held weapon or tool drawn in front of the first-person camera (Unreal FPS template / Unity
## FPS Microgame "view model"). A child of the camera: it bobs with your steps, lags behind mouse
## look, lowers while sprinting or riding, and swings or recoils when you attack. Uses the same
## item -> model table as the third-person hand (CharacterModel.HELD_MODELS), never casts shadows.

const FirstPersonView = preload("res://scripts/client/first_person_view.gd")
const CharacterModel = preload("res://scripts/client/character_model.gd")

## Where the grip rests relative to the eye: right, down and forward.
const REST := Vector3(0.24, -0.25, -0.46)
const LOWERED := Vector3(0.18, -0.52, -0.38)

var _item_id := "__none__"
var _pivot: Node3D
var _held: Node3D
var _sway := Vector2.ZERO
var _look_relative := Vector2.ZERO
var _attack_t := -1.0
var _attack_ranged := false
var _lower := 0.0


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)


## Shows the model for an item id ("" or an unknown item hides the hands).
func set_item(item_id: String) -> void:
	if item_id == _item_id:
		return
	_item_id = item_id
	if _held != null:
		_held.queue_free()
		_held = null
	_held = make_item(item_id)
	if _held != null:
		_pivot.add_child(_held)


## A fresh, shadowless node for an item, oriented with the blade/barrel pointing away from the eye; null if none.
static func make_item(item_id: String) -> Node3D:
	if item_id == "":
		return null
	var held: Node3D
	var key := ""
	if item_id == "fishing_rod":
		held = CharacterModel._fishing_rod()
	else:
		key = str(CharacterModel.HELD_MODELS.get(CharacterModel.weapon_family(item_id), ""))
		if key == "":
			return null
		var path: String = ("res://assets/models/kaykit_weapons/%s.gltf" if key.begins_with("kaykit:") else "res://assets/kenney/fps/%s.glb") % key.get_slice(":", 1)
		if not ResourceLoader.exists(path):
			return null
		var scene := load(path) as PackedScene
		if scene == null:
			return null
		held = scene.instantiate() as Node3D
	var size: float = float(CharacterModel.HELD_SCALES.get(key, 0.5)) * 0.55 # A touch smaller: it is right at the eye.
	var root := Node3D.new()
	root.name = "Held_" + item_id
	if key.begins_with("kenney:"):
		held.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * size), Vector3.ZERO) # Barrel forward (-Z).
	elif key.contains("bow"):
		held.transform = Transform3D(Basis(Vector3.FORWARD, 0.25).scaled(Vector3.ONE * size), Vector3(-0.08, 0.0, 0.0))
	else:
		# Blades and shafts rise from the fist and lean away from the eye, like a ready stance.
		held.transform = Transform3D((Basis(Vector3.RIGHT, -0.55) * Basis(Vector3.FORWARD, -0.3)).scaled(Vector3.ONE * size), Vector3.ZERO)
	root.add_child(held)
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func has_item() -> bool:
	return _held != null


## Mouse motion this frame (pixels), for the lag behind the view.
func add_look(relative: Vector2) -> void:
	_look_relative += relative


func play_attack(ranged: bool) -> void:
	_attack_t = 0.0
	_attack_ranged = ranged


## Per frame: `bob` from FirstPersonView.head_bob, `lowered` while sprinting/riding/swimming.
func update_pose(delta: float, bob: Vector2, lowered: bool) -> void:
	var d := maxf(delta, 0.0)
	_sway = _sway.lerp(FirstPersonView.viewmodel_sway(_look_relative), 1.0 - exp(-10.0 * d))
	_look_relative = Vector2.ZERO
	_lower = move_toward(_lower, 1.0 if lowered else 0.0, d * 4.0)
	var attack := Vector3.ZERO
	if _attack_t >= 0.0:
		_attack_t += d
		attack = FirstPersonView.attack_pose(_attack_t, _attack_ranged)
		if _attack_t > 0.5:
			_attack_t = -1.0
	var rest := REST.lerp(LOWERED, _lower)
	# The hands bob a little more than the head, in counter-phase sideways, which reads as weight.
	_pivot.position = rest + Vector3(-bob.x * 1.4, bob.y * 1.6, attack.x)
	_pivot.rotation = Vector3(_sway.y + attack.y - _lower * 0.6, _sway.x + attack.z, -_sway.x * 0.6)
