# vehicle_dynamics.gd

> Pure-math vehicle dynamics: raycast suspension, Pacejka "magic formula" tires with a friction circle, engine torque curve, auto gearbox, differential, brakes...

`res://scripts/shared/vehicle_dynamics.gd`

## Overview

```text
Pure-math vehicle dynamics: raycast suspension, Pacejka "magic formula" tires with a
friction circle, engine torque curve, auto gearbox, differential, brakes and anti-roll bars.
No scene-tree or physics-server dependency; the world is queried through a ground Callable
so the whole model runs headless and deterministically.

Conventions: body-local forward is -Z, right is +X, up is +Y (Godot). Steer input +1 turns
LEFT (positive yaw about +Y). Wheel positions are relative to the centre of mass.

Credits (concepts and public data only; no third-party code copied):
 - Marco Monster, "Car Physics for Games" (2003): slip ratio / slip angle, traction curve,
   weight transfer, drivetrain torque chain, friction ellipse. Public-domain style article.
 - Hans B. Pacejka, "Tyre and Vehicle Dynamics": the magic formula
   F = D sin(C atan(Bx - E(Bx - atan(Bx)))); B/C/E values here are typical published
   magnitudes (B~10-12, C~1.4-1.65), not copied from a licensed dataset.
 - Racer (Ruud van Gaal) docs: wheel spin integration with an implicit tire term.
 - Ideas for raycast suspension and anti-roll bars follow the common spring/damper model
   (e.g. MIT-licensed Godot/Bullet raycast-vehicle write-ups); implemented from scratch.
```

## Constants

- `const GRAVITY: float = 9.81`
- `const RAD_S_TO_RPM: float = 9.549296585513721`
- `const DRIVE_EFFICIENCY: float = 0.9`

## Classes

- `class WheelState extends RefCounted:`

## Functions

### `pacejka`

```gdscript
static func pacejka(x: float, b: float, c: float, d: float, e: float) -> float
```

Pacejka magic formula. x is slip (ratio or radians), d the peak force, returns force.

### `tire_force`

```gdscript
static func tire_force(kappa: float, alpha: float, load: float, tire: Dictionary, mu_scale: float = 1.0) -> Vector2
```

Combined-slip tire force. Returns Vector2(longitudinal, lateral); the lateral component
has the sign of the slip angle (caller applies it against the side velocity). The force
vector is limited by a friction circle of radius mu * load.

### `setup`

```gdscript
func setup(config: Dictionary) -> void
```

### `reset`

```gdscript
func reset(pos: Vector3, bas: Basis = Basis.IDENTITY) -> void
```

Places the vehicle at `pos` with zero motion and parked wheels.

### `static_ride_height`

```gdscript
func static_ride_height() -> float
```

Approximate body-origin height above flat ground at static equilibrium.

### `wheel_count`

```gdscript
func wheel_count() -> int
```

### `torque_at`

```gdscript
func torque_at(rpm: float) -> float
```

### `step`

```gdscript
func step(dt: float, inputs: Dictionary, ground: Callable) -> void
```

### `telemetry`

```gdscript
func telemetry() -> Dictionary
```

UI telemetry snapshot.

_3 private function(s) starting with `_` are not listed._
