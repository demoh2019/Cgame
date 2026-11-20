extends Node
## Sound: positional effects for what the server announces, footsteps and ambience for the local player.

const Assets = preload("res://scripts/client/assets.gd")
const Defs = preload("res://scripts/shared/defs.gd")

var _ambience: AudioStreamPlayer
var _steps: AudioStreamPlayer
var _footsteps_wanted := false
var enabled := true

# Music (Fantasy RPG Music Vol. 2, imported into assets/packs/music by tools/import_downloads.sh; silent without it).
# Two players crossfade between moods: calm by day, eerie at night, drums while fighting.
const MUSIC := {
	"day": ["Light Ambient 1 (Loop)", "Light Ambient 2 (Loop)", "Light Ambient 3 (Loop)"],
	"night": ["Night Ambient 2 (Loop)", "Night Ambient 3 (Loop)"],
	"combat": ["Action 1 (Loop)", "Action 2 (Loop)"],
}
const MUSIC_DB := -17.0
const COMBAT_SECONDS := 9.0 # Fighting music keeps going this long after the last blow.
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _mood := ""
var _daylight := 1.0
var _combat_left := 0.0


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
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.volume_db = -80.0
		add_child(player)
		_music.append(player)


static func music_track(track: String) -> AudioStream:
	var path := Assets.PACKS + "music/" + track + ".mp3"
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStreamMP3
	if stream != null:
		stream.loop = true
	return stream


## Called every frame with the light level; picks the mood and fades toward it.
func update_music(daylight: float, delta: float) -> void:
	_daylight = daylight
	_combat_left = maxf(_combat_left - delta, 0.0)
	var mood := "combat" if _combat_left > 0.0 else ("day" if _daylight > 0.3 else "night")
	if mood != _mood and enabled:
		var tracks: Array = MUSIC[mood]
		var stream := music_track(String(tracks[randi() % tracks.size()]))
		if stream != null:
			_mood = mood
			_music_active = 1 - _music_active
			_music[_music_active].stream = stream
			_music[_music_active].volume_db = -40.0
			_music[_music_active].play()
	# Fade the new track in and the old one out over about two seconds (faster into a fight).
	var rate: float = delta * (30.0 if _mood == "combat" else 14.0)
	for i in _music.size():
		var player := _music[i]
		if not player.playing:
			continue
		var target: float = MUSIC_DB if (i == _music_active and enabled) else -60.0
		player.volume_db = move_toward(player.volume_db, target, rate)
		if player.volume_db <= -59.0 and i != _music_active:
			player.stop()


func mark_combat() -> void:
	_combat_left = COMBAT_SECONDS


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
			if event.get("peer", -1) == local_peer:
				mark_combat()
			play_at("blaster" if event.get("ranged", false) else "break", position, -4.0 if event.get("ranged", false) else -14.0)
		"hit":
			if event.get("kind", "") == "zombie":
				play_at("enemy_hurt", position, -4.0)
			elif event.get("id", -1) == local_peer:
				mark_combat()
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
