extends Node
## Sound: positional effects for what the server announces, footsteps and ambience for the local player.

const Assets = preload("res://scripts/client/assets.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const ReverbZones = preload("res://scripts/client/reverb_zones.gd")
const AudioMix = preload("res://scripts/client/audio_mix.gd")
const AudioSurfaces = preload("res://scripts/client/audio_surfaces.gd")
const AudioVoices = preload("res://scripts/client/audio_voices.gd")
const AudioSpatial = preload("res://scripts/client/audio_spatial.gd")
const AudioDucking = preload("res://scripts/client/audio_ducking.gd")
const AudioAmbient = preload("res://scripts/client/audio_ambient.gd")
const EngineFeatures = preload("res://scripts/client/engine_features.gd")
## Optional engine SoundConcurrencyManager (null on a binary without the gameplay_fx module).
const CONCURRENCY_GROUPS := {"enemy_hurt": 4, "coin": 3, "blaster": 4, "blaster_repeater": 4, "break": 3}
var _concurrency: Node = null
var _concurrency_tried := false
var _sfx_bus := -1
var _sfx_lowpass := -1
var _rain: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _voices: Array = [] # Active 3D sources, including bounded obstacle probes.
# Unreal-style sound obstruction checks: only static geometry on layer 1,
# no per-frame physics casts for every active sound.
const OBSTRUCTION_RAYS_PER_TICK := 3
const OBSTRUCTION_RECHECK_SECONDS := 0.25
const OBSTRUCTION_GEOMETRY_MASK := 1
var _obstruction_clock := 0.0
var _listener := Vector3.ZERO
var _ground := Callable()
var _humidity := 0.0
var _duck_target := 0.0
var _duck := 0.0
var _duck_hold := 0.0
var _surface := "grass"
var _cutoff := AudioSpatial.OPEN_CUTOFF

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
	AudioMix.ensure_buses()
	_sfx_bus = ReverbZones.ensure_bus()
	_sfx_lowpass = AudioMix.ensure_lowpass(ReverbZones.BUS)
	AudioMix.load_all()
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	_ambience.stream = Assets.sound("ambience")
	_ambience.volume_db = -22.0
	add_child(_ambience)
	_steps = AudioStreamPlayer.new()
	_steps.stream = Assets.sound("walking")
	_steps.volume_db = -14.0
	_steps.bus = ReverbZones.BUS
	add_child(_steps)
	if _ambience.stream is AudioStreamOggVorbis:
		(_ambience.stream as AudioStreamOggVorbis).loop = true
	if _steps.stream is AudioStreamOggVorbis:
		(_steps.stream as AudioStreamOggVorbis).loop = true
	_ambience.play()
	_rain = _noise_loop(0.0, 7)
	_wind = _noise_loop(0.93, 11)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = MUSIC_DB
	add_child(_music)
	var adaptive := _adaptive_music()
	if adaptive != null:
		_music.stream = adaptive


## A silent looping generated-noise player on the Ambience bus (rain hiss / wind rumble).
func _noise_loop(smooth: float, noise_seed: int) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = AudioAmbient.noise_stream(2.0, smooth, noise_seed)
	player.bus = "Ambience"
	player.volume_db = -80.0
	add_child(player)
	player.play()
	return player


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
	player.bus = "Music"
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
	var distance := position.distance_to(_listener)
	# Voice limiting: cull the quietest/oldest voice, or drop this one when it is the weakest.
	var loudness := AudioVoices.audibility(volume_db, distance, player.unit_size)
	var now := Time.get_ticks_msec() / 1000.0
	var snapshot: Array = []
	for v in _voices:
		snapshot.append({"name": v["name"], "audibility": v["audibility"], "age": now - float(v["born"])})
	var cull := AudioVoices.victim(snapshot, sound_name, loudness)
	if cull == AudioVoices.DROP_NEW:
		player.free()
		return
	if cull >= 0:
		var old: Dictionary = _voices[cull]
		_voices.remove_at(cull)
		if is_instance_valid(old["player"]):
			(old["player"] as Node).queue_free()
	# Random pitch and volume per shot, then air absorption and terrain occlusion on the source itself.
	var variation := AudioVoices.variation(randf(), randf())
	player.pitch_scale = variation["pitch"]
	player.volume_db = volume_db + float(variation["db"])
	var occluded: bool = _ground.is_valid() and AudioSpatial.terrain_blocked(_listener + Vector3(0, 1.6, 0), position, _ground)
	player.attenuation_filter_cutoff_hz = AudioSpatial.source_cutoff(distance, occluded, _humidity)
	player.attenuation_filter_db = -18.0 if occluded else -24.0
	_ensure_concurrency()
	if _concurrency != null and not bool(_concurrency.call("request_play", StringName(sound_name), player, position, _listener)):
		player.free()
		return
	add_child(player)
	player.global_position = position
	var record := {
		"player": player, "name": sound_name, "audibility": loudness, "born": now,
		"terrain_blocked": occluded,
		"obstruction": 0.0,
		"target_obstruction": 1.0 if occluded else 0.0,
		"next_obstruction_check": 0.0,
		"original_db": player.volume_db,
		"original_cutoff": player.attenuation_filter_cutoff_hz
	}
	_voices.append(record)
	player.finished.connect(func() -> void:
		_voices.erase(record)
		player.queue_free())
	player.play()


## Scene physics is read only during physics ticks. This detects wooden
## barricades, ruins and dungeon walls in addition to the existing terrain
## heightfield obstruction, without querying on every audio mixer update.
## The native engine handles the actual volume/low-pass response. Stock
## Godot receives the identical effect via its standard player properties.
func _physics_process(delta: float) -> void:
	if not enabled or _voices.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	_obstruction_clock += minf(delta, 0.1)
	var viewport: Viewport = get_viewport()
	var world: World3D = viewport.world_3d if viewport != null else null
	var state: PhysicsDirectSpaceState3D = world.direct_space_state if world != null else null
	var rays: int = 0
	for index in _voices.size():
		var record: Dictionary = _voices[index]
		var player: AudioStreamPlayer3D = record.get("player") as AudioStreamPlayer3D
		if not is_instance_valid(player) or not player.is_playing():
			continue
		var target: float = float(record.get("target_obstruction", 0.0))
		if state != null and rays < OBSTRUCTION_RAYS_PER_TICK \
				and _obstruction_clock >= float(record.get("next_obstruction_check", 0.0)):
			var listener_eye: Vector3 = _listener + Vector3(0.0, 1.6, 0.0)
			var source_eye: Vector3 = player.global_position + Vector3(0.0, 0.5, 0.0)
			# Include world obstacles and barriers, not Area3D triggers.
			# Impacts very near the source are the source's own floor/prop.
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				listener_eye, source_eye, OBSTRUCTION_GEOMETRY_MASK)
			ray.collide_with_areas = false
			var hit: Dictionary = state.intersect_ray(ray)
			var blocked: bool = not hit.is_empty() and \
				(hit.get("position", source_eye) as Vector3).distance_to(source_eye) > 0.75
			target = 1.0 if blocked or bool(record["terrain_blocked"]) else 0.0
			record["target_obstruction"] = target
			record["next_obstruction_check"] = _obstruction_clock + OBSTRUCTION_RECHECK_SECONDS
			rays += 1
		# Smooth changes to prevent a harsh click when crossing a doorway.
		var old_amount: float = float(record.get("obstruction", 0.0))
		var amount: float = move_toward(old_amount, target, delta * 6.0)
		if absf(amount - old_amount) > 0.0001:
			record["obstruction"] = amount
			if player.has_method("set_obstruction_amount"):
				player.call("set_obstruction_amount", amount)
			else:
				var base_cutoff: float = float(record["original_cutoff"])
				player.attenuation_filter_cutoff_hz = AudioSpatial.obstruction_cutoff(base_cutoff, amount)
				player.volume_db = float(record["original_db"]) + AudioSpatial.obstruction_db(amount)
		_voices[index] = record


## Creates the engine SoundConcurrencyManager once, when the binary has it; victims it stops are freed here.
func _ensure_concurrency() -> void:
	if _concurrency_tried:
		return
	_concurrency_tried = true
	_concurrency = EngineFeatures.make("SoundConcurrencyManager") as Node
	if _concurrency == null:
		return
	add_child(_concurrency)
	_concurrency.connect("voice_stopped", func(stopped: Node) -> void:
		if is_instance_valid(stopped):
			stopped.queue_free())
	for group in CONCURRENCY_GROUPS:
		var rule := EngineFeatures.make("SoundConcurrency", {
			"max_count": int(CONCURRENCY_GROUPS[group]), "resolution_rule": 1, "volume_scale": 0.85}) as Resource
		_concurrency.call("set_group_config", StringName(group), rule)


func play_ui(sound_name: String, volume_db: float = -6.0) -> void:
	if not enabled:
		return
	var player := AudioStreamPlayer.new()
	player.stream = Assets.sound(sound_name)
	player.volume_db = volume_db
	player.bus = "UI"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Glides world-sound reverb toward the listener's acoustic zone (cave, forest, open ground).
func update_reverb(underground: bool, biome: String, delta: float) -> void:
	ReverbZones.blend(ReverbZones.reverb(_sfx_bus), ReverbZones.zone_for(underground, biome), 1.0 - exp(-2.0 * delta))


## Per-frame environment audio: listener filtering, surface footsteps, weather loops, biome bed, music ducking.
## `storm` 0..1, `wind` is the wind speed, `covered` = sheltered or underground.
func update_environment(listener: Vector3, ground_height: Callable, underground: bool, biome: String,
		daylight: float, storm: float, wind: float, covered: bool, speed: float, delta: float) -> void:
	_listener = listener
	_ground = ground_height
	_humidity = clampf(storm, 0.0, 1.0)
	# Listener low-pass on the SFX bus (underground / storm).
	_cutoff = AudioSpatial.glide(_cutoff, AudioSpatial.listener_cutoff(underground, storm), delta)
	var lowpass := AudioServer.get_bus_effect(_sfx_bus, _sfx_lowpass) as AudioEffectLowPassFilter if _sfx_lowpass >= 0 else null
	if lowpass != null:
		lowpass.cutoff_hz = _cutoff
	# Surface footsteps retune the walking loop.
	var h := float(ground_height.call(listener.x, listener.z)) if ground_height.is_valid() else 1.0
	_surface = AudioSurfaces.surface_for(underground, biome, h, Defs.WATER_LEVEL)
	var profile := AudioSurfaces.profile(_surface)
	_steps.pitch_scale = AudioSurfaces.speed_pitch(float(profile["pitch"]), speed)
	_steps.volume_db = float(profile["db"])
	# Biome ambience bed, rain and wind loops.
	var bed := AudioAmbient.bed(biome, daylight, underground)
	_ambience.pitch_scale = lerpf(_ambience.pitch_scale, float(bed["pitch"]), 1.0 - exp(-1.5 * delta))
	_ambience.volume_db = lerpf(_ambience.volume_db, float(bed["db"]), 1.0 - exp(-1.5 * delta))
	_rain.volume_db = lerpf(_rain.volume_db, AudioAmbient.rain_db(storm, covered), 1.0 - exp(-2.0 * delta))
	_wind.volume_db = lerpf(_wind.volume_db, AudioAmbient.wind_db(wind, storm, underground), 1.0 - exp(-2.0 * delta))
	# Sidechain-style ducking of music and ambience.
	_duck_hold = maxf(_duck_hold - delta, 0.0)
	if _duck_hold <= 0.0:
		_duck_target = 0.0
	_duck = AudioDucking.step(_duck, _duck_target, delta)
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus != -1:
		AudioServer.set_bus_volume_db(music_bus, AudioMix.linear_to_db(AudioMix.volumes["Music"]) + _duck if AudioMix.volumes["Music"] > 0.0001 else -80.0)
	var amb_bus := AudioServer.get_bus_index("Ambience")
	if amb_bus != -1:
		AudioServer.set_bus_volume_db(amb_bus, AudioMix.linear_to_db(AudioMix.volumes["Ambience"]) + _duck * 0.4 if AudioMix.volumes["Ambience"] > 0.0001 else -80.0)


## Dips music for a big event (kept for HOLD seconds, deepest dip wins).
func duck(depth_db: float) -> void:
	if depth_db < _duck_target:
		_duck_target = depth_db
	if depth_db < 0.0:
		_duck_hold = AudioDucking.HOLD


var _slider := 0


## Ctrl+Home picks the next volume slider (Master/Music/SFX/UI/Ambience), Ctrl+PageUp/PageDown change it.
## Returns the message to show, or "" when the key is not an audio shortcut.
func handle_key(event: InputEventKey) -> String:
	if not event.ctrl_pressed:
		return ""
	var bus: String = AudioMix.SLIDERS[_slider]
	match event.keycode:
		KEY_HOME:
			_slider = (_slider + 1) % AudioMix.SLIDERS.size()
			bus = AudioMix.SLIDERS[_slider]
		KEY_PAGEUP:
			AudioMix.nudge(bus, 0.1)
		KEY_PAGEDOWN:
			AudioMix.nudge(bus, -0.1)
		_:
			return ""
	return "Volume %s: %d%% (Ctrl+Home bus, Ctrl+PgUp/PgDn)" % [bus, roundi(float(AudioMix.volumes[bus]) * 100.0)]


func surface() -> String:
	return _surface


## Reacts to one server event. `height` is the ground height used for positions without one.
func on_event(event: Dictionary, local_peer: int, ground_height: Callable) -> void:
	_ground = ground_height
	if event.get("peer", local_peer) == local_peer or event["type"] in ["zombie_died", "knockback"]:
		duck(AudioDucking.depth_for(str(event["type"])))
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
