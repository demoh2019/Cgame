# audio_voices.gd

> Voice limiting and per-shot variation (Unity AudioSource priority + max voices / Unreal Sound Concurrency).

`res://scripts/client/audio_voices.gd`

## Overview

Voice limiting and per-shot variation (Unity AudioSource priority + max voices / Unreal Sound Concurrency).

## Constants

- `const MAX_VOICES := 24`
- `const SAME_SOUND_MAX := 5`
- `const ROOM := -2 # victim(): nothing to cull, the new voice may start.`
- `const DROP_NEW := -1 # victim(): the new voice itself is the one to drop.`
- `const STEAL_HOLD_SECONDS := 0.12`
- `const STEAL_EARLY_OVERRIDE_DB := 12.0`

## Functions

### `variation`

```gdscript
static func variation(roll1: float, roll2: float, pitch_range: float = 0.08, db_range: float = 1.5) -> Dictionary
```

Random pitch/volume jitter so repeated one-shots do not sound machine-gunned. `roll1`/`roll2` are 0..1.

### `audibility`

```gdscript
static func audibility(volume_db: float, distance: float, unit_size: float = 14.0) -> float
```

Loudness a voice has at the listener: volume minus a simple distance rolloff. Lower = first to be culled.

### `victim`

```gdscript
static func victim(voices: Array, name: String, new_audibility: float, max_voices: int = MAX_VOICES, same_max: int = SAME_SOUND_MAX) -> int
```

Index in `voices` (dicts with "name", "audibility", "age") to cull so a new voice of `name` with
`new_audibility` may start; ROOM when nothing needs culling, DROP_NEW when the new voice is the weakest.

### `priority_for`

```gdscript
static func priority_for(name: String) -> int
```

Local-only event priority for spatial audio concurrency.

### `prioritized_victim`

```gdscript
static func prioritized_victim(voices: Array, name: String, new_db: float, new_priority: int, max_voices: int = MAX_VOICES, same_max: int = SAME_SOUND_MAX) -> int
```

Pure policy matching native AudioVoiceAdmissionPlanner. Same-sound caps
take precedence over the shared active pool, then priority and audibility.

### `prioritized_victim_stable`

```gdscript
static func prioritized_victim_stable(voices: Array, name: String, new_db: float, new_priority: int, max_voices: int = MAX_VOICES, same_max: int = SAME_SOUND_MAX, min_voice_age: float = STEAL_HOLD_SECONDS, early_override_db: float = STEAL_EARLY_OVERRIDE_DB) -> int
```

Preserve newly-started voice attacks briefly unless the next voice has
higher priority or is substantially louder. Data-only, no AudioServer calls.

_2 private function(s) starting with `_` are not listed._
