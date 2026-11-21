# audio_ducking.gd

> Sidechain-style ducking (Unity AudioMixer Duck Volume / Unreal Sound Mix + Submix Sidechain).

`res://scripts/client/audio_ducking.gd`

## Overview

Sidechain-style ducking (Unity AudioMixer Duck Volume / Unreal Sound Mix + Submix Sidechain).
Big events dip the music (and ambience a little) for a moment, then it recovers.

## Constants

- `const DEPTH_DB := {"death": -12.0, "outpost_taken": -8.0, "skill_up": -6.0, "knockback": -4.0, "zombie_died": -3.0}`
- `const ATTACK := 40.0 # dB per second going down (fast),`
- `const RELEASE := 4.0 # and coming back (slow).`
- `const HOLD := 1.2    # seconds a dip is held before release.`

## Functions

### `depth_for`

```gdscript
static func depth_for(event_type: String) -> float
```

### `step`

```gdscript
static func step(current: float, target: float, delta: float) -> float
```

New duck amount in dB (<= 0) moving toward `target` (the deepest active dip, 0 = none).

### `trigger_source`

```gdscript
static func trigger_source(sources: Dictionary, source: String, depth_db: float, hold_seconds: float = HOLD) -> bool
```

Native AudioDuckMix parity fallback: independent, named duck sources.
A repeated event refreshes its hold, preserving its previous deeper dip.
A single invalid source never mutates another live event.

### `target_sources`

```gdscript
static func target_sources(sources: Dictionary) -> float
```

### `tick_sources`

```gdscript
static func tick_sources(sources: Dictionary, current: float, delta: float) -> float
```

Advance before mixing: sources expiring exactly at this tick have no hold.

