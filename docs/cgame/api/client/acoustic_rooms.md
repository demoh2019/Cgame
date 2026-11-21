# acoustic_rooms.gd

> Geometric room acoustics: RT60 from box geometry and synthetic impulse responses.

`res://scripts/client/acoustic_rooms.gd`

## Overview

Geometric room acoustics: RT60 from box geometry and synthetic impulse responses.

Sources (formulas only, no code copied): W. C. Sabine reverberation equation
T60 = 0.161 V / A; C. F. Eyring (1930) T60 = 0.161 V / (-S ln(1 - a_mean));
mean free path 4V/S (Kuttruff, Room Acoustics); typical octave-band absorption
coefficients from public acoustics handbooks (rounded, approximate); the
Wwise Rooms & Portals and Steam Audio documentation for the overall concept.
Written from scratch for this project.

## Constants

- `const SPEED_OF_SOUND := 343.0`
- `const SABINE_K := 0.161`
- `const DEFAULT_MATERIAL := "concrete"`
- `const MATERIALS := {` - Absorption per material as Vector3(low ~125 Hz, mid ~1 kHz, high ~4 kHz).

## Functions

### `room_from_box`

```gdscript
static func room_from_box(size: Vector3, absorption: Dictionary) -> Dictionary
```

`absorption` maps a surface ("floor", "ceiling", "walls") to a material name
or directly to a Vector3 of band coefficients. Missing surfaces use concrete.

### `impulse_response`

```gdscript
static func impulse_response(rt60: Vector3, sample_rate: int, seconds: float, seed: int) -> PackedFloat32Array
```

Synthetic impulse response: noise split into three bands, each decaying
60 dB over its own RT60 (x = low, y = mid, z = high). Peak-normalised to 1.

_3 private function(s) starting with `_` are not listed._
