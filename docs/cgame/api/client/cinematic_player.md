# cinematic_player.gd

> Plays a cinematic_sequence.gd timeline onto bound nodes.

`res://scripts/client/cinematic_player.gd`

## Overview

Plays a cinematic_sequence.gd timeline onto bound nodes.
Bindings map track / camera names to Node3D / Camera3D / AnimationPlayer.
Float tracks named "fov", "focus_distance", "aperture", "exposure" drive the
current camera (fov, and DOF/exposure via CameraAttributesPractical when
present); "binding:property" drives any property of a bound node.

## Signals

- `signal event_fired(event_name: String, args: Array)`
- `signal finished`

## Functions

### `play`

```gdscript
func play(seq: RefCounted, bind: Dictionary) -> void
```

### `stop`

```gdscript
func stop() -> void
```

### `pause`

```gdscript
func pause() -> void
```

### `resume`

```gdscript
func resume() -> void
```

### `seek`

```gdscript
func seek(t: float) -> void
```

### `advance`

```gdscript
func advance(delta: float) -> void
```

### `current_camera`

```gdscript
func current_camera() -> Camera3D
```

_5 private function(s) starting with `_` are not listed._
