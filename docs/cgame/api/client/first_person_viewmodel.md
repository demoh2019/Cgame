# first_person_viewmodel.gd

> The held weapon or tool drawn in front of the first-person camera (Unreal FPS template / Unity FPS Microgame "view model").

`res://scripts/client/first_person_viewmodel.gd`

## Overview

The held weapon or tool drawn in front of the first-person camera (Unreal FPS template / Unity
FPS Microgame "view model"). A child of the camera: it bobs with your steps, lags behind mouse
look, lowers while sprinting or riding, and swings or recoils when you attack. Uses the same
item -> model table as the third-person hand (CharacterModel.HELD_MODELS), never casts shadows.

## Constants

- `const FirstPersonView = preload("res://scripts/client/first_person_view.gd")`
- `const CharacterModel = preload("res://scripts/client/character_model.gd")`
- `const REST := Vector3(0.24, -0.25, -0.46)` - Where the grip rests relative to the eye: right, down and forward.
- `const LOWERED := Vector3(0.18, -0.52, -0.38)`

## Functions

### `set_item`

```gdscript
func set_item(item_id: String) -> void
```

Shows the model for an item id ("" or an unknown item hides the hands).

### `make_item`

```gdscript
static func make_item(item_id: String) -> Node3D
```

A fresh, shadowless node for an item, oriented with the blade/barrel pointing away from the eye; null if none.

### `has_item`

```gdscript
func has_item() -> bool
```

### `add_look`

```gdscript
func add_look(relative: Vector2) -> void
```

Mouse motion this frame (pixels), for the lag behind the view.

### `play_attack`

```gdscript
func play_attack(ranged: bool) -> void
```

### `update_pose`

```gdscript
func update_pose(delta: float, bob: Vector2, lowered: bool) -> void
```

Per frame: `bob` from FirstPersonView.head_bob, `lowered` while sprinting/riding/swimming.

_1 private function(s) starting with `_` are not listed._
