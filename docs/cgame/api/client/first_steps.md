# first_steps.gd

> Guided first session: eight short goals that teach the core loop (gather -> refine -> craft -> arm -> build -> take a risk -> trade/store).

`res://scripts/client/first_steps.gd`

## Overview

Guided first session: eight short goals that teach the core loop (gather -> refine -> craft ->
arm -> build -> take a risk -> trade/store). Each goal completes by itself from the client's
own state, so it never needs server changes, and progress is remembered between sessions.
Shown as the top line of the HUD quest card; F3 skips the guide.

## Constants

- `const SAVE_PATH := "user://first_steps.cfg"`
- `const STEPS := [`

## Functions

### `load_state`

```gdscript
static func load_state() -> void
```

### `save_state`

```gdscript
static func save_state() -> void
```

### `active`

```gdscript
static func active() -> bool
```

### `current_text`

```gdscript
static func current_text() -> String
```

### `skip`

```gdscript
static func skip() -> void
```

### `note_deposit`

```gdscript
static func note_deposit() -> void
```

The stash was used (a deposit result came back ok).

### `goal_met`

```gdscript
static func goal_met(client) -> bool
```

Whether the current goal is met by the client's state.

### `update`

```gdscript
static func update(client) -> int
```

Advances past every goal already met. Returns the number of goals just completed.

_1 private function(s) starting with `_` are not listed._
