# effect_application_rules.gd

> (no header comment)

`res://scripts/shared/effect_application_rules.gd`

## Constants

- `const CROWD := "Effect.CrowdControl"` - Native Unreal-style Gameplay Effect application gates for server-owned PvE statuses. Static, validated rule cache. Stock Godot uses identical fail-closed rules.
- `const STAGGER := "Effect.CrowdControl.Stagger"`
- `const SNARE := "Effect.CrowdControl.Snare"`
- `const SUNDER := "Effect.Debuff.Sunder"`

## Functions

### `can_apply`

```gdscript
static func can_apply(effect: String, alive: bool, raid_boss: bool, extra_tags: PackedStringArray = PackedStringArray()) -> bool
```

Only the server calls this for actual gameplay. The additional tag array
permits future buffs/gear to grant scoped immunity without engine edits.

### `native_reason`

```gdscript
static func native_reason(effect: String, alive: bool, raid_boss: bool, extra_tags: PackedStringArray = PackedStringArray()) -> String
```

_2 private function(s) starting with `_` are not listed._
