extends Node
## Sound: positional effects for what the server announces, footsteps and ambience for the local player.

const Assets = preload("res://scripts/client/assets.gd")
const Defs = preload("res://scripts/shared/defs.gd")

var _ambience: AudioStreamPlayer
var _steps: AudioStreamPlayer
var _footsteps_wanted := false
var enabled := true


func _ready() -> void:
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = Assets.sound("ambience")
	_ambience.volume_db = -22.0
	add_child(_ambience)
	_steps = AudioStreamPlayer.new()
	_steps.stream = Assets.sound("walking")
	_steps.volume_db = -14.0
	add_child(_steps)
	if _ambience.stream is AudioStreamOggVorbis:
		(_ambience.stream as AudioStreamOggVorbis).loop = true
	if _steps.stream is AudioStreamOggVorbis:
		(_steps.stream as AudioStreamOggVorbis).loop = true
	_ambience.play()


func set_footsteps(active: bool) -> void:
	if active == _footsteps_wanted:
		return
	_footsteps_wanted = active
	if active:
		_steps.play()
	else:
		_steps.stop()


func play_at(sound_name: String, position: Vector3, volume_db: float = 0.0) -> void:
	if not enabled:
		return
	var stream := Assets.sound(sound_name)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 14.0
	player.max_distance = 90.0
	add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


func play_ui(sound_name: String, volume_db: float = -6.0) -> void:
	if not enabled:
		return
	var player := AudioStreamPlayer.new()
	player.stream = Assets.sound(sound_name)
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Reacts to one server event. `height` is the ground height used for positions without one.
func on_event(event: Dictionary, local_peer: int, ground_height: Callable) -> void:
	var position := Vector3.ZERO
	if event.has("x") and event.has("z"):
		position = Vector3(event["x"], float(ground_height.call(event["x"], event["z"])) + 1.0, event["z"])
	match event["type"]:
		"attack":
			play_at("blaster" if event.get("ranged", false) else "break", position, -4.0 if event.get("ranged", false) else -14.0)
		"hit":
			if event.get("kind", "") == "zombie":
				play_at("enemy_hurt", position, -4.0)
			elif event.get("id", -1) == local_peer:
				play_ui("enemy_attack", -4.0)
		"zombie_died":
			play_at("enemy_destroy", position, -2.0)
		"gathered":
			play_ui("coin", -8.0)
		"crate":
			play_ui("weapon_change", -6.0)
		"death":
			if event.get("peer", -1) == local_peer:
				play_ui("fall", -2.0)
