# audio_virtual_voices.gd

> Audio source virtualization (Wwise/FMOD virtual voices, UE5 "Play When Silent" virtualization): a long sound refused because every voice is busy keeps advanc...

`res://scripts/client/audio_virtual_voices.gd`

## Overview

Audio source virtualization (Wwise/FMOD virtual voices, UE5 "Play When
Silent" virtualization): a long sound refused because every voice is busy
keeps advancing its playback time silently and is promoted into a real
voice — at the right offset — as soon as one frees up while it still runs.

## Constants

- `const MIN_LENGTH := 1.5 # Short one-shots are simply dropped.`
- `const MAX_VIRTUAL := 24`

## Functions

### `add`

```gdscript
func add(sound_name: String, position: Vector3, volume_db: float, now: float, length: float) -> bool
```

### `expire`

```gdscript
func expire(now: float) -> void
```

### `promote`

```gdscript
func promote(now: float, listener: Vector3) -> Dictionary
```

Takes the loudest still-running virtual voice for the listener; {} if none.
The result's "offset" is where real playback must resume.

