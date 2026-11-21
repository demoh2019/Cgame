# local_server.gd

> (no header comment)

`res://scripts/client/local_server.gd`

## Constants

- `const SoloSlots = preload("res://scripts/client/solo_slots.gd")`
- `const PORT := SoloSlots.BASE_PORT`
- `const NAKAMA_PORT := 7350`
- `const STOP_WAIT_MS := 2200`

## Functions

### `nakama_available`

```gdscript
static func nakama_available(port: int = NAKAMA_PORT) -> bool
```

Whether a Nakama backend accepts connections on this machine (a quick TCP check, no request).

### `server_arguments`

```gdscript
static func server_arguments(project_path: String, port: int, with_nakama: bool, slot: int = 1) -> PackedStringArray
```

The arguments for the headless server process (exposed for tests).

### `start`

```gdscript
func start(slot: int = 1) -> String
```

Starts the server; returns the address to connect to, or "" when the process could not start.

### `is_running`

```gdscript
func is_running() -> bool
```

### `stop`

```gdscript
func stop() -> void
```

