# first_person_view.gd

> First-person camera maths for the local survivor.

`res://scripts/client/first_person_view.gd`

## Overview

First-person camera maths for the local survivor. Pure functions so the
mapping between mouse look, WASD and the server's yaw convention is testable.

Server yaw convention: facing = Vector2(sin(yaw), cos(yaw)) on the XZ plane.
Input convention (UiAccess.read_move): x = right, y = back (screen down).

## Constants

- `const EYE_HEIGHT := 1.62`
- `const CROUCH_EYE_HEIGHT := 1.1`
- `const MOUNTED_EYE_HEIGHT := 2.05`
- `const MAX_PITCH := 1.45`
- `const MOUSE_SENSITIVITY := 0.0025`
- `const JUMP_SECONDS := 0.55`
- `const JUMP_HEIGHT := 0.75`
- `const FOV_DEFAULT := 75.0`
- `const FOV_MIN := 60.0`
- `const FOV_MAX := 110.0`
- `const NEAR_CLIP := 0.05 # The held item sits ~0.4 m from the eye.`
- `const BOB_STRIDE := 1.9 # Metres per full step cycle (two footfalls).`
- `const BOB_HEIGHT := 0.045`
- `const BOB_SIDE := 0.03`
- `const MAX_ROLL := 0.035 # Radians of strafe lean.`
- `const LAND_DIP := 0.12`

## Functions

### `forward`

```gdscript
static func forward(yaw: float) -> Vector2
```

Forward direction on the XZ plane for a yaw.

### `right`

```gdscript
static func right(yaw: float) -> Vector2
```

Right-hand direction on the XZ plane for a yaw.

### `to_world_move`

```gdscript
static func to_world_move(move: Vector2, yaw: float) -> Vector2
```

Turns screen-relative WASD into the world-axis move the server expects.

### `apply_look`

```gdscript
static func apply_look(yaw: float, pitch: float, relative: Vector2, sensitivity: float = MOUSE_SENSITIVITY) -> Vector2
```

Applies mouse motion to yaw/pitch. Returns Vector2(yaw, pitch).

### `eye_height`

```gdscript
static func eye_height(crouching: bool, mounted: bool) -> float
```

### `camera_transform`

```gdscript
static func camera_transform(feet: Vector3, yaw: float, pitch: float, height: float) -> Transform3D
```

Camera transform at the survivor's eyes looking along yaw/pitch.

### `jump_offset`

```gdscript
static func jump_offset(t: float) -> float
```

Vertical camera offset for a cosmetic hop; t < 0 means on the ground.

### `make_crosshair`

```gdscript
static func make_crosshair() -> Control
```

A small centred cross that shows where attacks and spells will go.

### `fov`

```gdscript
static func fov(setting: float) -> float
```

The vertical FOV the first-person camera uses (the isometric view keeps its own narrow lens).

### `look_sensitivity`

```gdscript
static func look_sensitivity(multiplier: float, invert_y: bool) -> Vector2
```

Radians per pixel for mouse look from the settings multiplier, negative pitch scale when Y is inverted.

### `apply_look_scaled`

```gdscript
static func apply_look_scaled(yaw: float, pitch: float, relative: Vector2, sensitivity: Vector2) -> Vector2
```

Mouse look with separate horizontal/vertical sensitivity (from look_sensitivity). Returns Vector2(yaw, pitch).

### `advance_bob_phase`

```gdscript
static func advance_bob_phase(phase: float, speed: float, delta: float) -> float
```

Advances the step phase (radians) by distance walked; one full cycle per BOB_STRIDE metres.

### `head_bob`

```gdscript
static func head_bob(phase: float, speed: float, enabled: bool = true) -> Vector2
```

Head bob offset at a step phase: Vector2(side, up). Fades in with speed and is off when `enabled` is false.

### `strafe_roll`

```gdscript
static func strafe_roll(lateral_speed: float, enabled: bool = true) -> float
```

Camera roll from sideways speed relative to the view (m/s, + right): lean into the strafe.

### `landing_dip`

```gdscript
static func landing_dip(t: float) -> float
```

Landing dip: a quick drop and spring back over 0.35 s after `t` seconds; 0 outside.

### `crosshair_spread`

```gdscript
static func crosshair_spread(speed: float, airborne: bool) -> float
```

Crosshair gap in pixels: tight standing still, opens with speed and in the air.

### `viewmodel_sway`

```gdscript
static func viewmodel_sway(look_relative: Vector2) -> Vector2
```

Held-item sway: the item lags behind mouse motion (pixels this frame), clamped. Returns Vector2(yaw, pitch) radians.

### `attack_pose`

```gdscript
static func attack_pose(t: float, ranged: bool) -> Vector3
```

Attack animation of the held item at `t` seconds into it: Vector3(back kick m, pitch rad, side swing rad).
Ranged: a short recoil kick; melee: a wind-up then a fast diagonal slash.

### `set_body_shadow_only`

```gdscript
static func set_body_shadow_only(model: Node, enabled: bool) -> void
```

Shadow-only body for the local survivor in first person: other players still see it, you see its shadow.

### `layout_crosshair`

```gdscript
static func layout_crosshair(root: Control, gap: float, hit: float) -> void
```

Re-lays the make_crosshair bars for a gap (px) and a hit-marker strength 0..1 (bars turn red-white and splay).

