# VehicleWheel3D combined-slip tire grip (Cgame)

## Purpose

Real tire force is not two unrelated force budgets: heavy braking and
acceleration consume grip that would otherwise be available for steering.
Jolt Physics exposes independent longitudinal and lateral tire friction.

Cgame's existing Godot/Bullet-derived raycast wheel calculation already
contains a combined circle/ellipse, but it had a pure-longitudinal-slip
bug: the last skid correction was gated on nonzero side impulse. A car
could accelerate with an uncapped forward impulse if it had no lateral
slip. This revision fixes the issue and allows independent per-wheel
forward/backward and lateral grip multipliers, defaulting to the prior
behavior for ordinary mixed impulse conditions.

This is a simple coupled impulse ellipse, not a Pacejka tire curve.

## Wheel inspector properties

Existing property: wheel_friction_slip (default 10.5).

New properties, both default 1.0:
- wheel_longitudinal_grip: [0,4], scales forward braking/acceleration.
- wheel_lateral_grip: [0,4], scales cornering grip.

Example GDScript:

    $VehicleWheel3D.wheel_longitudinal_grip = 1.0
    $VehicleWheel3D.wheel_lateral_grip = 0.65

Zero on either direction disables only that direction of tire impulse.

## Physical model

Given N = suspension_force * physics_delta and mu = wheel_friction_slip:

    forward_budget = 2 * N * mu * wheel_longitudinal_grip
    side_budget = N * mu * wheel_lateral_grip
    q = hypot(forward_impulse/forward_budget,
              side_impulse/side_budget)

When q > 1, both requested impulses scale by 1/q. The factor of 2
on forward grip preserves the pre-existing VehicleBody3D weighting
(fwdFactor=0.5). The skid diagnostic measures the smallest fraction
actually applied relative to the original requested impulse.

A zero budget clips that direction to zero. Invalid numeric values
produce zero tire impulses instead of injecting non-finite numbers into
the physics solver. A single O(wheel_count) pass replaces the previous
two-pass skid correction.

## Scope

- Works with the raycast VehicleBody3D / VehicleWheel3D path.
- Does not add dynamic tire angular slip, transient tire relaxation,
  wheel camber, realistic tire-road temperature or pressure, an engine,
  gearbox or drivetrain.
- Does not change the existing TODO for applying equal-and-opposite
  wheel friction impulses to a dynamic ground body.
- Coefficients greater than 1 can represent unrealistically strong
  tires and should be tuned cautiously.

## Validation

Production C++ helper:
servers/physics_vehicle_combined_tire_grip.h

Doctest:
tests/servers/test_physics_vehicle_combined_tire_grip.cpp

Standalone compiler/run:
g++ -std=c++17 -O2 -Wall -Wextra -Werror -I. tests/stress/test_physics_vehicle_combined_tire_grip_compiler.cpp -o /tmp/combined_tire && /tmp/combined_tire

Python numerical + source integration:
python3 -m unittest discover -s tests/stress -p 'test_physics_vehicle_combined_tire_grip.py' -v

Next: tire slip curves, friction-combination against contacted surface,
dynamic-ground reaction impulses and load-sensitive tire force.
