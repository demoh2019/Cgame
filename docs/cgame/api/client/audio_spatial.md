# audio_spatial.gd

> Spatial filtering: terrain occlusion, distance air absorption and the listener's own muffling (Unity Audio Low Pass + occlusion plugins / Unreal Sound Attenu...

`res://scripts/client/audio_spatial.gd`

## Overview

Spatial filtering: terrain occlusion, distance air absorption and the listener's own muffling
(Unity Audio Low Pass + occlusion plugins / Unreal Sound Attenuation: Air Absorption + Occlusion).

## Constants

- `const OPEN_CUTOFF := 20500.0`
- `const MUFFLED_CUTOFF := 1400.0`
- `const OCCLUDED_GAIN_DB := -8.0`
- `const OBSTRUCTION_ATTACK_SECONDS := 0.08`
- `const OBSTRUCTION_RELEASE_SECONDS := 0.22`

## Functions

### `terrain_blocked`

```gdscript
static func terrain_blocked(from: Vector3, to: Vector3, height_at: Callable, steps: int = 8, margin: float = 0.4) -> bool
```

True when the straight line from listener to source dips below the terrain somewhere between them.

### `source_cutoff`

```gdscript
static func source_cutoff(distance: float, occluded: bool, humidity: float = 0.0) -> float
```

Cutoff for a source: drops with distance (air absorbs highs, more so in rain/fog) and when occluded.

### `obstruction_cutoff`

```gdscript
static func obstruction_cutoff(base_cutoff: float, amount: float) -> float
```

Matches the native AudioOcclusionPolicy's per-source log-frequency
response when the game runs on a standard Godot build.

### `obstruction_db`

```gdscript
static func obstruction_db(amount: float) -> float
```

### `smooth_obstruction`

```gdscript
static func smooth_obstruction(current: float, target: float, delta: float, attack_seconds: float = OBSTRUCTION_ATTACK_SECONDS, release_seconds: float = OBSTRUCTION_RELEASE_SECONDS) -> float
```

Stock Godot fallback for native AudioStreamPlayer3D.advance_obstruction_amount.
Exponential integration is independent of frame and physics tick rate.

### `listener_cutoff`

```gdscript
static func listener_cutoff(underground: bool, storm: float) -> float
```

Bus low-pass target for the listener: muffled underground, slightly dulled in a storm.

### `glide`

```gdscript
static func glide(current: float, target: float, delta: float, rate: float = 4.0) -> float
```

Frame-rate independent glide in the log-frequency domain (pitch perception is logarithmic).

