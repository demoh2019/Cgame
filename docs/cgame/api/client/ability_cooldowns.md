# ability_cooldowns.gd

> (no header comment)

`res://scripts/client/ability_cooldowns.gd`

## Constants

- `const SLOT_TAGS := {` - Read-only client bridge for authoritative ability cooldowns. Never grants ability use: the server validates all requests.
- `const GROUP_TAG := "Ability.Global"`
- `const FEEDBACK_SECONDS := 0.22`
- `const FEEDBACK_PREFIX := "Local.UI.Activation."`

## Functions

### `make_native`

```gdscript
static func make_native() -> Object
```

### `raw_remaining`

```gdscript
static func raw_remaining(slot: String, you: Dictionary) -> float
```

### `snapshot`

```gdscript
static func snapshot(you: Dictionary) -> Dictionary
```

The shared lock only exists when the server sends ability_global_cd.

### `format_remaining`

```gdscript
static func format_remaining(seconds: float) -> String
```

### `display_remaining`

```gdscript
static func display_remaining(slot: String, you: Dictionary, tracker: Object = null) -> float
```

### `display_many`

```gdscript
static func display_many(slots: PackedStringArray, you: Dictionary, tracker: Object = null) -> PackedFloat64Array
```

Read the entire five-slot bar with one native bridge call, keeping the
shared authoritative group lock. Older native builds and stock Godot use
the same per-slot policy. Invalid slot lists fail closed.

### `reconcile_native`

```gdscript
static func reconcile_native(tracker: Object, you: Dictionary) -> bool
```

Scoped reconciliation: server owns Ability.*, while Local.* may hold
short client-side button feedback. Older forks use whole snapshots.

### `record_activation_feedback`

```gdscript
static func record_activation_feedback(tracker: Object, slot: String) -> bool
```

Records a short visual press, NOT an ability cooldown. The server still
accepts or rejects the ability independently; the UI must not infer success.

### `activation_feedback_active`

```gdscript
static func activation_feedback_active(tracker: Object, slot: String) -> bool
```

_1 private function(s) starting with `_` are not listed._
