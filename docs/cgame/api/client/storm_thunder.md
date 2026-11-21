# storm_thunder.gd

> (no header comment)

`res://scripts/client/storm_thunder.gd`

## Constants

- `const StormLightning = preload("res://scripts/shared/storm_lightning.gd")` - World-space, speed-of-sound thunder for authoritative lightning_struck events. The flash remains immediate; the sound wave arrives later. Unreal-style distance delay + 3D sound emitter, procedural/no asset pack.
- `const SAMPLE_RATE := 22050`
- `const SAMPLE_SECONDS := 3.0`
- `const MAX_DISTANCE := StormLightning.THUNDER_MAX_DISTANCE`
- `const MAX_PENDING := 4`
- `const MAX_VOICES := 2`
- `const REFERENCE_TEMPERATURE_C := 20.0`

## Functions

### `propagation_delay`

```gdscript
static func propagation_delay(distance_m: float, temperature_c: float = 20.0) -> float
```

Audio travels around 343 m/s at 20 C; 343 m => ~1 second delay.
The native module validates range and temperature. Exactly the same
bounded fallback works in stock Godot and on dedicated test runners.

### `thunder_wave`

```gdscript
static func thunder_wave() -> AudioStreamWAV
```

A one-time three-second mono pulse: sub-bass turbulence, rolling rumble,
and a brief noisy crack. It is deterministic, non-looping and reused by
every thunder voice. No licensed audio asset or real-time DSP allocation.

### `on_strike`

```gdscript
func on_strike(event: Dictionary, listener: Vector3, height_at: Callable, underground: bool) -> bool
```

Only a genuine server-confirmed strike (or its server-quantized
distant atmospheric echo) schedules thunder. A warning never generates
sound and underground listeners hear no outdoor impact.

### `queued_count`

```gdscript
func queued_count() -> int
```

_2 private function(s) starting with `_` are not listed._
