# gameplay_cues.gd

> (no header comment)

`res://scripts/client/gameplay_cues.gd`

## Constants

- `const STATUS_TAGS := {` - Presentation-only Unreal-style Gameplay Cues bridge. The server owns statuses, damage and network replication; cues only trigger VFX.
- `const PULSE_TAGS := {`
- `const PULSE_PRIORITY := {` - Niagara-style effect priority: visible Resolve stacks beat ambient debuff pulses during cue queue saturation; no combat or status value changes.

## Functions

### `attach`

```gdscript
static func attach(node: Node) -> void
```

### `active_snapshot`

```gdscript
static func active_snapshot(kind: String, state: Dictionary) -> Dictionary
```

Source of truth is the replicated actor's current status, not an invented timer.

### `sync`

```gdscript
static func sync(node: Node, kind: String, state: Dictionary) -> void
```

### `frame_events`

```gdscript
static func frame_events(node: Node, periodic: Dictionary) -> Array
```

Bridge repeated native EffectTimeline pulse counts to one cue per tag.
Stock Godot keeps periodic VFX through a compatibility event array.

### `pulse_color`

```gdscript
static func pulse_color(cue_tag: String) -> Color
```

