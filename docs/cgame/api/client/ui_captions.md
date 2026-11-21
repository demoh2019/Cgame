# ui_captions.gd

> Closed captions for important sounds with a direction relative to the camera, e.g.

`res://scripts/client/ui_captions.gd`

## Overview

Closed captions for important sounds with a direction relative to the camera, e.g. "[Gunshot, left, 24 m]"
(Unity has no built-in equivalent; Unreal ships Subtitles/Closed Captions and sound-class captions).
Pure static functions turn a server event into text; `CaptionView` shows the last few lines.

## Constants

- `const UiLocalization = preload("res://scripts/client/ui_localization.gd")`
- `const SECTORS := ["ahead", "ahead-right", "right", "behind-right", "behind", "behind-left", "left", "ahead-left"]`
- `const NEARBY_M := 2.5`
- `const MAX_RANGE_M := 120.0`

## Classes

- `class CaptionView extends VBoxContainer:` - A small bottom-centre caption strip (a Control, so it follows UI scale).

## Functions

### `direction_word`

```gdscript
static func direction_word(offset: Vector2, forward: Vector2, right: Vector2) -> String
```

Direction word for an offset in world XZ given the camera's forward/right vectors flattened to XZ.

### `caption_key`

```gdscript
static func caption_key(event: Dictionary, local_peer: int) -> String
```

English caption key for an event, or "" when it makes no important sound.

### `caption_for`

```gdscript
static func caption_for(event: Dictionary, local_peer: int, listener: Vector2, forward: Vector2, right: Vector2, locale: String = "") -> String
```

Full caption line or "". `listener` is the player's XZ, `forward`/`right` the camera basis flattened to XZ.

### `push_line`

```gdscript
static func push_line(lines: Array, text: String, now: float, window: float = 0.8, limit: int = 4) -> Array
```

Lines kept on screen: newest last, duplicates within `window` seconds merged, at most `limit` rows.

