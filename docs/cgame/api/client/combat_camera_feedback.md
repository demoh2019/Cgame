# combat_camera_feedback.gd

> Cosmetic-only server-event reactions, like Unreal's Gameplay Cues.

`res://scripts/client/combat_camera_feedback.gd`

## Overview

Cosmetic-only server-event reactions, like Unreal's Gameplay Cues.
Nearby impacts feel powerful; distant ones smoothly fade, not hard cut at
arbitrary metre thresholds. No gameplay damage, network state, or scene
nodes are modified. Uses the Cgame native camera trauma path when available.

## Constants

- `const PROFILES := {`

## Functions

### `falloff`

```gdscript
static func falloff(distance: float, inner_radius: float, outer_radius: float) -> float
```

Same smoothstep attenuation as CameraShake::spatial_falloff; used only by
stock Godot fallback (the native fork computes it without script work).

### `apply`

```gdscript
static func apply(camera: Camera3D, kind: String, source: Vector3, listener: Vector3, shake_scale: float) -> void
```

Mutates only the camera's *visual* trauma, never the player's transform.
The UI accessibility preference scales the impulse before it reaches C++.

