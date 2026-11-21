# network_snapshot_smoothing.gd

> Jitter-buffered visual smoothing for replicated players and enemies.

`res://scripts/client/network_snapshot_smoothing.gd`

## Overview

Jitter-buffered visual smoothing for replicated players and enemies.
Endpoints are server-authoritative; no prediction, movement or physics edits.
Unreal simulated-proxy smoothing + Gaffer Hermite snapshots, bounded to
prevent curve overshoot at walls, teleport gates and rapid turnarounds.

## Constants

- `const TELEPORT_DISTANCE := 8.0`
- `const MAX_SAMPLE_SECONDS := 0.5`

## Functions

### `hermite`

```gdscript
static func hermite(from: Vector3, to: Vector3, v_from: Vector3, v_to: Vector3, span: float, alpha: float, host: Node3D = null) -> Vector3
```

### `sample_position`

```gdscript
static func sample_position(previous: Array, older: Array, newer: Array, following: Array, alpha: float, host: Node3D = null) -> Vector3
```

Each sample is [server_time, Vector3 position, yaw]. Extra samples provide
better endpoint velocity estimates; two samples reproduce the original
straight linear path exactly. Never derive tangents across a teleport.

_1 private function(s) starting with `_` are not listed._
