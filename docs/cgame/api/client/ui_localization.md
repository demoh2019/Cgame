# ui_localization.gd

> Russian/English interface strings built in code (no CSV import step).

`res://scripts/client/ui_localization.gd`

## Overview

Russian/English interface strings built in code (no CSV import step). The English text itself is the message
key, so every existing Label, Button and tooltip whose text matches is translated by the engine as soon as the
locale changes (Godot auto-translate) without editing the code that creates it. Equivalent to the Unity
Localization package string tables and Unreal's FText string tables.

## Constants

- `const UiSettings = preload("res://scripts/client/ui_settings.gd")`
- `const RU := {`

## Functions

### `detect_locale`

```gdscript
static func detect_locale() -> String
```

### `install`

```gdscript
static func install() -> void
```

Builds the Russian Translation and registers it with the TranslationServer (idempotent).

### `set_locale`

```gdscript
static func set_locale(code: String, persist: bool = true) -> void
```

### `apply_saved`

```gdscript
static func apply_saved() -> void
```

### `t`

```gdscript
static func t(key: String, locale: String = "") -> String
```

Looks a string up directly (no scene tree needed); falls back to the English key.

### `missing_entries`

```gdscript
static func missing_entries() -> Array
```

Entries with an empty value; used by the unit test to catch a blank translation.

