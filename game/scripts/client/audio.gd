extends Node
## Sound: positional effects for what the server announces, footsteps and ambience for the local player.

const Assets = preload("res://scripts/client/assets.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const ReverbZones = preload("res://scripts/client/reverb_zones.gd")
var _sfx_bus := -1

var _ambience: AudioStreamPlayer
var _steps: AudioStreamPlayer
var _footsteps_wanted := false
var enabled := true

# Music (Fantasy RPG Music Vol. 2, imported into assets/packs/music by tools/import_downloads.sh; silent without it).
# One AudioStreamInteractive (the engine's adaptive music) holds a clip per mood, calm by day, eerie at night, drums
# while fighting, and crossfades between them itself when the mood changes.
const MUSIC := {
	"day": ["Light Ambient 1 (Loop)", "Light Ambient 2 (Loop)", "Light Ambient 3 (Loop)"],
	"night": ["Night Ambient 2 (Loop)", "Night Ambient 3 (Loop)"],
	"combat": ["Action 1 (Loop)", "Action 2 (Loop)"],
}
const MUSIC_DB := -17.0
const COMBAT_SECONDS := 9.0 # Fighting music keeps going this long after the last blow.
var _music: AudioStreamPlayer
var _mood := ""
var _daylight := 1.0
var _combat_left := 0.0


func _ready() -> void:
	_sfx_bus = ReverbZones.ensure_bus()
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
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	add_child(_music)
	var adaptive := _adaptive_music()
	if adaptive != null:
		_music.stream = adaptive


## The day, night and combat clips (one track each, picked at random), with a crossfade from any clip to any other:
## two seconds between calm moods, one into a fight.
func _adaptive_music() -> AudioStreamInteractive:
	var moods: Array = MUSIC.keys()
	var music := AudioStreamInteractive.new()
	music.clip_count = moods.size()
	for i in moods.size():
		var tracks: Array = MUSIC[moods[i]]
		var stream := music_track(String(tracks[randi() % tracks.size()]))
		if stream == null:
			return null
		stream.bpm = 60.0 # So a beat is a second for the fade lengths below.
		music.set_clip_name(i, moods[i])
		music.set_clip_stream(i, stream)
	music.add_transition(AudioStreamInteractive.CLIP_ANY, AudioStreamInteractive.CLIP_ANY,
		AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE, AudioStreamInteractive.TRANSITION_TO_TIME_START,
		AudioStreamInteractive.FADE_CROSS, 2.0)
	var combat: int = moods.find("combat")
	music.add_transition(AudioStreamInteractive.CLIP_ANY, combat,
		AudioStreamInteractive.TRANSITION_FROM_TIME_IMMEDIATE, AudioStreamInteractive.TRANSITION_TO_TIME_START,
		AudioStreamInteractive.FADE_CROSS, 1.0)
	music.initial_clip = moods.find("day")
	return music


static func music_track(track: String) -> AudioStream:
	var path := Assets.PACKS + "music/" + track + ".mp3"
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStreamMP3
	if stream != null:
		stream.loop = true
	return stream


## Called every frame with the light level; picks the mood and lets the adaptive stream fade to it.
func update_music(daylight: float, delta: float) -> void:
	_daylight = daylight
	_combat_left = maxf(_combat_left - delta, 0.0)
	if _music.stream == null:
		return
	if not enabled:
		_music.stop()
		_mood = ""
		return
	var mood := "combat" if _combat_left > 0.0 else ("day" if _daylight > 0.3 else "night")
	if not _music.playing:
		_music.play()
		_mood = ""
	if mood != _mood:
		_mood = mood
		var playback := _music.get_stream_playback() as AudioStreamPlaybackInteractive
		if playback != null:
			playback.switch_to_clip_by_name(mood)


## A short musical phrase over everything (death, a level gained, a victory). Silent without the music pack.
func play_sting(track: String, volume_db: float = -9.0) -> void:
	if not enabled:
		return
	var path := Assets.PACKS + "music/" + track + ".mp3"
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


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
	player.bus = ReverbZones.BUS
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


## Glides world-sound reverb toward the listener's acoustic zone (cave, forest, open ground).
func update_reverb(underground: bool, biome: String, delta: float) -> void:
	ReverbZones.blend(ReverbZones.reverb(_sfx_bus), ReverbZones.zone_for(underground, biome), 1.0 - exp(-2.0 * delta))


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
		"barricade_broken", "snare_triggered":
			play_at("break", position, -4.0)
		"flash_thrown":
			play_at("blaster_repeater", position, -6.0)
		"knockback":
			play_at("enemy_hurt", position, -8.0)
		"restoration_pulse":
			play_at("coin", position, -6.0)
		"outpost_taken":
			play_ui("weapon_change", -6.0)
		"gathered":
			play_ui("coin", -8.0)
		"crate":
			play_ui("weapon_change", -6.0)
		"death":
			if event.get("peer", -1) == local_peer:
				play_ui("fall", -2.0)
				play_sting("Death")
		"skill_up":
			if event.get("peer", -1) == local_peer:
				play_sting("Complete", -12.0)
		"outpost_taken":
			play_sting("Victory", -10.0)
