# facial_animation.gd

> Layered facial animation graph driving blend shapes (ARKit-style 52-shape names).

`res://scripts/client/facial_animation.gd`

## Overview

```text
Layered facial animation graph driving blend shapes (ARKit-style 52-shape names).
Layers, evaluated in order and clamped to 0..1 at the end:
  1. base emotion pose (FACS action units -> blend shapes)
  2. additive pain / aggression layers
  3. visemes from lip_sync.gd (A-H + X)
  4. procedural blinks (deterministic random interval 2-6 s)
  5. eye saccades (deterministic micro-targets)

Concepts from the Facial Action Coding System (Ekman & Friesen; public research taxonomy),
the Apple ARKit blend-shape naming convention, and Oculus/Rhubarb viseme shapes
(Rhubarb Lip Sync, Daniel Wolf, MIT, https://github.com/DanielSWolf/rhubarb-lip-sync).
Clean-room implementation; no third-party code copied.
```

## Constants

- `const BLINK_DURATION := 0.2`
- `const BLINK_MIN_INTERVAL := 2.0`
- `const BLINK_MAX_INTERVAL := 6.0`
- `const SACCADE_MIN_INTERVAL := 0.4`
- `const SACCADE_MAX_INTERVAL := 2.0`
- `const SACCADE_TRAVEL := 0.04`
- `const SACCADE_AMPLITUDE := 0.35`
- `const AU_SHAPES := {` - FACS action unit -> {blend shape: weight at AU intensity 1}.
- `const EMOTIONS := {` - Emotion -> {AU: intensity}.
- `const PAIN_AUS := {"AU1": 0.5, "AU4": 0.6, "AU6": 0.4, "AU7": 0.8, "AU20": 0.6, "AU10": 0.3}`
- `const AGGRESSION_AUS := {"AU4": 0.8, "AU7": 0.4, "AU9": 0.5, "AU10": 0.5, "AU23": 0.5}`
- `const VISEME_SHAPES := {` - Viseme (A-H, X) -> blend shapes.

## Functions

### `evaluate`

```gdscript
func evaluate(t: float, emotion: String, emotion_weight: float, viseme_weights: Dictionary) -> Dictionary
```

### `blink_weight`

```gdscript
func blink_weight(t: float) -> float
```

### `gaze_at`

```gdscript
func gaze_at(t: float) -> Vector2
```

Eye look target (x, y) in -1..1 at time t.

### `apply_to`

```gdscript
func apply_to(mesh_instance: MeshInstance3D, weights: Dictionary) -> int
```

_7 private function(s) starting with `_` are not listed._
