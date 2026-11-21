# loot_drop_bounce.gd

> Loot bags land with a physics-style bounce when they first appear (Unity: a dropped Rigidbody with a bouncy PhysicMaterial; Unreal: a spawned physics actor).

`res://scripts/client/loot_drop_bounce.gd`

## Overview

Loot bags land with a physics-style bounce when they first appear (Unity: a dropped Rigidbody with a bouncy
PhysicMaterial; Unreal: a spawned physics actor). Analytic damped bounce on the bag's visual mesh only: the
entity's own position is the server's and is never touched, and Low quality skips it.

## Constants

- `const DROP_HEIGHT := 1.4`
- `const GRAVITY := 14.0`
- `const RESTITUTION := 0.45`
- `const SQUASH := 0.18`
- `const MIN_BOUNCE := 0.03 # Metres: below this the bag rests.`

## Functions

### `height`

```gdscript
static func height(age: float, drop_height: float = DROP_HEIGHT) -> float
```

Height above the resting spot `age` seconds after being dropped (ball bouncing with restitution).

### `settle_time`

```gdscript
static func settle_time(drop_height: float = DROP_HEIGHT) -> float
```

Seconds until the bag is at rest.

### `squash`

```gdscript
static func squash(age: float) -> float
```

Vertical squash factor right as the bag touches down (1 = none), recovering over a short window.

### `apply`

```gdscript
static func apply(bag: Node3D, delta: float, level: int) -> void
```

Drive the first child mesh of a bag node. `level` is the graphics tier; call every frame.

