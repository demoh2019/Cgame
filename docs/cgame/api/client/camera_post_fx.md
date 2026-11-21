# camera_post_fx.gd

> Gameplay camera and post-processing feel: the Cinemachine (look-ahead, impulse, FOV, zoom) and URP/HDRP Volume / Unreal Post Process Volume (vignette, chroma...

`res://scripts/client/camera_post_fx.gd`

## Overview

Gameplay camera and post-processing feel: the Cinemachine (look-ahead, impulse, FOV, zoom) and URP/HDRP Volume /
Unreal Post Process Volume (vignette, chromatic aberration, motion blur, desaturation) behaviours, driven by what
happens to the local player. Pure maths lives in static helpers (tested); the node owns the overlay and the camera.

## Constants

- `const SHADER := preload("res://assets/shaders/camera_post_fx.gdshader")`
- `const BASE_FOV := 38.0`
- `const LOW_HEALTH_START := 40.0`
- `const MAX_LOOK_AHEAD := 2.6`

## Documented variables

- `var look := Vector3.ZERO` - Added to the camera target (look-ahead).
- `var zoom_mul := 1.0` - Multiplies the camera distance (speed pull-out).
- `var cold := 0.0` - 0..1 set by the client from altitude/snow/night (see breath_vapor.gd).

## Functions

### `hurt_intensity`

```gdscript
static func hurt_intensity(damage: float) -> float
```

Red flash strength for a hit of `damage` HP (a scratch still reads, a big hit saturates).

### `low_health_amount`

```gdscript
static func low_health_amount(health: float, start: float = LOW_HEALTH_START) -> float
```

0 at or above the threshold, rising to 1 at death's door.

### `heartbeat`

```gdscript
static func heartbeat(time: float, amount: float) -> float
```

Double-thump pulse in 0..1, faster as health drops. Zero when `amount` is zero.

### `decay`

```gdscript
static func decay(value: float, delta: float, rate: float) -> float
```

Exponential decay towards zero, frame-rate independent.

### `hit_stop`

```gdscript
static func hit_stop(damage: float, killed: bool, mine: bool) -> Vector2
```

Brief freeze for an impact: Vector2(real seconds, time scale). Zero duration means no hit-stop.

### `stop_active`

```gdscript
static func stop_active(now_msec: int, until_msec: int) -> bool
```

Whether a hit-stop is still running at `now` (msec).

### `fov_target`

```gdscript
static func fov_target(base: float, sprinting: bool, riding: bool, speed: float) -> float
```

FOV kick: wider while sprinting, wider still on the bike, scaled by actual speed.

### `zoom_multiplier`

```gdscript
static func zoom_multiplier(sprinting: bool, riding: bool, speed: float) -> float
```

Distance pull-out so fast travel shows more road ahead.

### `look_ahead`

```gdscript
static func look_ahead(move_dir: Vector2, speed: float) -> Vector3
```

Cinemachine-style look-ahead: lead the target along the move direction (xz), capped.

### `radial_blur_amount`

```gdscript
static func radial_blur_amount(speed: float, sprinting: bool, riding: bool, level: int) -> float
```

Radial blur strength 0..1; only at speed, off on Low quality.

### `blur_taps`

```gdscript
static func blur_taps(level: int) -> int
```

Blur taps per quality tier (0 disables the loop in the shader).

### `letterbox_target`

```gdscript
static func letterbox_target(alive: bool) -> float
```

Letterbox target: bars slide in while dead (cinematic death), out when alive.

### `clamp_orbit`

```gdscript
static func clamp_orbit(yaw: float, pitch: float, dist: float) -> Vector3
```

Photo-mode orbit clamp: Vector3(yaw, pitch, distance).

### `setup`

```gdscript
func setup(main_camera: Camera3D, hud_layer: CanvasLayer = null) -> void
```

### `on_event`

```gdscript
func on_event(event: Dictionary, my_peer: int, distance: float) -> void
```

Feed gameplay events (the match block in online_main). `distance` is metres from the player to the event.

### `update`

```gdscript
func update(delta: float, you: Dictionary, move_input: Vector2, speed: float, quality_level: int) -> void
```

Per-frame update. `you` is the server state dict; read `look`/`zoom_mul`/`photo_active` afterwards.

### `toggle_photo`

```gdscript
func toggle_photo(player_pos: Vector3) -> void
```

Photo mode: free orbit around the player with the interface hidden. Ctrl+Alt+P toggles, Esc leaves.

### `photo_camera`

```gdscript
func photo_camera(cam: Camera3D, player_pos: Vector3) -> void
```

_3 private function(s) starting with `_` are not listed._
