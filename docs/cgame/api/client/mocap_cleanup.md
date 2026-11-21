# mocap_cleanup.gd

> Motion-capture cleanup toolkit: noise filtering, rotation smoothing, gap filling, spike removal, foot-skate cleanup, root-motion extraction, key reduction, r...

`res://scripts/client/mocap_cleanup.gd`

## Overview

```text
Motion-capture cleanup toolkit: noise filtering, rotation smoothing, gap filling,
spike removal, foot-skate cleanup, root-motion extraction, key reduction, retiming.
All functions are static and operate on whole tracks sampled at a constant fps.

Sources / credits (algorithms re-implemented from the published descriptions, no GPL code):
 - One Euro filter: Gery Casiez, Nicolas Roussel, Daniel Vogel, "1 Euro Filter" (CHI 2012).
   Reference implementation (1euro.js / OneEuroFilter.cpp) is BSD-3-Clause,
   Copyright (c) Gery Casiez. This port follows its structure (adaptive-cutoff
   exponential smoothing with a low-passed derivative).
 - Butterworth low-pass: RBJ "Audio EQ Cookbook" biquad coefficients (Robert
   Bristow-Johnson, public-domain-style cookbook formulas), Q = 1/sqrt(2); applied
   forward then backward (filtfilt-style, odd-reflection padding) for zero phase.
 - Ramer-Douglas-Peucker simplification (public-domain algorithm), applied in time.
 - Cubic Hermite / slerp gap filling and rotation-vector (log-map) filtering are
   textbook techniques.
No Apache-2.0 code is included.
```

## Constants

- `const TAU_F: float = TAU`

## Functions

### `one_euro_positions`

```gdscript
static func one_euro_positions(track: PackedVector3Array, fps: float, min_cutoff: float = 1.0, beta: float = 0.0, d_cutoff: float = 1.0) -> PackedVector3Array
```

Adaptive low-pass: low cutoff when slow (kills jitter), high cutoff when fast (low lag).

### `butterworth`

```gdscript
static func butterworth(track: PackedVector3Array, fps: float, cutoff_hz: float) -> PackedVector3Array
```

Zero-phase (forward + backward) 2nd-order Butterworth low-pass on a Vector3 track.
The effective order is 4 and the -3 dB point drops to about 0.64 * cutoff_hz.

### `make_continuous`

```gdscript
static func make_continuous(rots: Array[Quaternion]) -> Array[Quaternion]
```

Make a quaternion track hemisphere-consistent (q and -q are the same rotation).

### `smooth_rotations`

```gdscript
static func smooth_rotations(rots: Array[Quaternion], fps: float, cutoff: float) -> Array[Quaternion]
```

Low-pass a rotation track in the tangent space (rotation vectors) of the first sample,
so the result stays unit-length and sign flips (q vs -q) in the input are harmless.

### `remove_spikes`

```gdscript
static func remove_spikes(track: PackedVector3Array, threshold_sigma: float = 4.0) -> PackedVector3Array
```

Marks samples whose deviation from a 5-tap median exceeds threshold_sigma robust
sigmas (MAD based) and re-interpolates them.

### `fill_gaps`

```gdscript
static func fill_gaps(track: PackedVector3Array, valid: PackedByteArray) -> PackedVector3Array
```

Fills samples with valid[i] == 0 using cubic Hermite interpolation whose tangents come
from the valid neighbours. Leading/trailing gaps hold the nearest valid sample.

### `fill_gaps_rotations`

```gdscript
static func fill_gaps_rotations(rots: Array[Quaternion], valid: PackedByteArray) -> Array[Quaternion]
```

Rotation version of fill_gaps: slerp between the bracketing valid rotations.

### `detect_contacts`

```gdscript
static func detect_contacts(foot_track: PackedVector3Array, fps: float, height_threshold: float, speed_threshold: float) -> PackedByteArray
```

Contact = foot near the lowest height of the track AND moving slowly (units/second).
Runs shorter than three frames are dropped as noise.

### `fix_foot_skate`

```gdscript
static func fix_foot_skate(foot_track: PackedVector3Array, contacts: PackedByteArray, blend_frames: int = 4) -> PackedVector3Array
```

Locks every planted run to a single position (the run mean) and blends the correction
in before touchdown and out after lift-off so the foot does not pop.

### `extract_root_motion`

```gdscript
static func extract_root_motion(hips_track: PackedVector3Array) -> Dictionary
```

Splits hips motion into a ground-projected root (position + yaw from travel direction)
and hips relative to that root. yaw is the rotation about +Y taking +Z onto the travel
direction (forward = (sin yaw, 0, cos yaw)); it is unwrapped and held while stationary.

### `reduce_keys`

```gdscript
static func reduce_keys(track: PackedVector3Array, tolerance: float) -> PackedInt32Array
```

Ramer-Douglas-Peucker in time: keeps the fewest frame indices such that linear
interpolation between kept keys stays within tolerance of every dropped sample.

### `retime`

```gdscript
static func retime(track: PackedVector3Array, src_fps: float, dst_fps: float) -> PackedVector3Array
```

Resamples a track from src_fps to dst_fps using Catmull-Rom interpolation.

### `retime_rotations`

```gdscript
static func retime_rotations(rots: Array[Quaternion], src_fps: float, dst_fps: float) -> Array[Quaternion]
```

Rotation retime (slerp between neighbouring source frames).

_9 private function(s) starting with `_` are not listed._
