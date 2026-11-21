# client_prediction.gd

> Server-authoritative movement prediction (Overwatch / Quake / Gabriel Gambetta style).

`res://scripts/shared/client_prediction.gd`

## Overview

Server-authoritative movement prediction (Overwatch / Quake / Gabriel Gambetta style).
The client applies inputs locally at once and keeps them with sequence numbers. When the
server acknowledges `last_processed_seq` with its authoritative state, reconcile() drops the
acknowledged inputs and replays the remaining ones on top of the server state. The jump
between the old and the re-predicted position is not snapped but folded into a visual
offset that decays exponentially; errors above `error_threshold` snap instantly.

Design source: Gabriel Gambetta "Fast-Paced Multiplayer" and Valve/Overwatch GDC talks
(ideas only). Independent implementation, no third-party code, no license obligations.

apply: Callable(state: Dictionary, input: Dictionary, dt: float) -> Dictionary (deterministic,
must match the server's movement code). `position_key` names the float/Vector2/Vector3
entry in the state used for error measurement and smoothing.

## Documented variables

- `var smoothing_rate: float = 10.0` - visual offset decays as exp(-rate * dt)

## Functions

### `setup`

```gdscript
func setup(p_apply: Callable, initial_state: Dictionary, p_position_key: String = "pos", p_error_threshold: float = 2.0, p_smoothing_rate: float = 10.0) -> void
```

### `predict`

```gdscript
func predict(input: Dictionary, dt: float) -> int
```

Applies `input` locally and queues it. Returns its sequence number (send it to the server).

### `pending_count`

```gdscript
func pending_count() -> int
```

### `reconcile`

```gdscript
func reconcile(server_state: Dictionary, last_processed_seq: int) -> float
```

Server ack. Returns the position error (magnitude) between the old prediction and the
server-corrected re-prediction. Stale acks (older than the last one) are ignored.

### `update`

```gdscript
func update(delta: float) -> void
```

Decays the visual correction offset (call once per rendered frame).

### `offset_magnitude`

```gdscript
func offset_magnitude() -> float
```

### `visual_state`

```gdscript
func visual_state() -> Dictionary
```

Predicted state with the smoothed correction offset applied to the position entry.

_2 private function(s) starting with `_` are not listed._
