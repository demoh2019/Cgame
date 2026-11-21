# audio.gd

> Sound: positional effects for what the server announces, footsteps and ambience for the local player.

`res://scripts/client/audio.gd`

## Overview

Sound: positional effects for what the server announces, footsteps and ambience for the local player.

## Constants

- `const Assets = preload("res://scripts/client/assets.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const ReverbZones = preload("res://scripts/client/reverb_zones.gd")`
- `const AudioMix = preload("res://scripts/client/audio_mix.gd")`
- `const AudioSurfaces = preload("res://scripts/client/audio_surfaces.gd")`
- `const AudioVoices = preload("res://scripts/client/audio_voices.gd")`
- `const AudioVirtualVoices = preload("res://scripts/client/audio_virtual_voices.gd")`
- `const AudioSpatial = preload("res://scripts/client/audio_spatial.gd")`
- `const AudioDucking = preload("res://scripts/client/audio_ducking.gd")`
- `const AudioMixSnapshots = preload("res://scripts/client/audio_mix_snapshots.gd")`
- `const AudioAmbient = preload("res://scripts/client/audio_ambient.gd")`
- `const EngineFeatures = preload("res://scripts/client/engine_features.gd")`
- `const CONCURRENCY_GROUPS := {"enemy_hurt": 4, "coin": 3, "blaster": 4, "blaster_repeater": 4, "break": 3}` - Optional engine SoundConcurrencyManager (null on a binary without the gameplay_fx module).
- `const OBSTRUCTION_RAYS_PER_TICK := 3`
- `const OBSTRUCTION_RECHECK_SECONDS := 0.25`
- `const OBSTRUCTION_GEOMETRY_MASK := 1`
- `const MUSIC := {`
- `const MUSIC_DB := -17.0`
- `const COMBAT_SECONDS := 9.0 # Fighting music keeps going this long after the last blow.`
- `const FLESH := [preload("res://assets/gore/flesh_1.ogg"), preload("res://assets/gore/flesh_2.ogg"), preload("res://assets/gore/flesh_3.ogg")]` - Gore foley (CC0, assets/gore): wet flesh hits and bone cracks, with pitch variation.
- `const BONE := [preload("res://assets/gore/bone_break_1.ogg"), preload("res://assets/gore/bone_break_2.ogg"),`

## Functions

### `music_track`

```gdscript
static func music_track(track: String) -> AudioStream
```

### `update_music`

```gdscript
func update_music(daylight: float, delta: float) -> void
```

Called every frame with the light level; picks the mood and lets the adaptive stream fade to it.

### `play_sting`

```gdscript
func play_sting(track: String, volume_db: float = -9.0) -> void
```

A short musical phrase over everything (death, a level gained, a victory). Silent without the music pack.

### `mark_combat`

```gdscript
func mark_combat() -> void
```

### `set_footsteps`

```gdscript
func set_footsteps(active: bool) -> void
```

### `play_gore`

```gdscript
func play_gore(bone: bool, position: Vector3, volume_db: float = -6.0) -> void
```

### `get_voice_hold_rejections`

```gdscript
func get_voice_hold_rejections() -> int
```

### `play_at`

```gdscript
func play_at(sound_name: String, position: Vector3, volume_db: float = 0.0, from_position: float = 0.0) -> void
```

### `play_ui`

```gdscript
func play_ui(sound_name: String, volume_db: float = -6.0) -> void
```

### `update_reverb`

```gdscript
func update_reverb(underground: bool, biome: String, delta: float) -> void
```

Glides world-sound reverb toward the listener's acoustic zone (cave, forest, open ground).

### `update_environment`

```gdscript
func update_environment(listener: Vector3, ground_height: Callable, underground: bool, biome: String, daylight: float, storm: float, wind: float, covered: bool, speed: float, delta: float) -> void
```

Per-frame environment audio: listener filtering, surface footsteps, weather loops, biome bed, music ducking.
`storm` 0..1, `wind` is the wind speed, `covered` = sheltered or underground.

### `duck`

```gdscript
func duck(depth_db: float, source: String = "Generic") -> void
```

Dip music for one named event. Retrigger resets only that source's hold.
Legacy call sites without a name keep the established shared "Generic" key.

### `handle_key`

```gdscript
func handle_key(event: InputEventKey) -> String
```

Ctrl+Home picks the next volume slider (Master/Music/SFX/UI/Ambience), Ctrl+PageUp/PageDown change it.
Returns the message to show, or "" when the key is not an audio shortcut.

### `surface`

```gdscript
func surface() -> String
```

### `on_event`

```gdscript
func on_event(event: Dictionary, local_peer: int, ground_height: Callable) -> void
```

Reacts to one server event. `height` is the ground height used for positions without one.

_13 private function(s) starting with `_` are not listed._
