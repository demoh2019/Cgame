# GodotPhysics2D / GodotPhysics3D: maximum dynamic angular velocity

Following Jolt's MotionProperties max angular velocity, Cgame exposes an
optional, space-wide spin-speed cap for the built-in GodotPhysics backends.

- `physics/2d/solver/max_angular_velocity` — radians/second
- `physics/3d/solver/max_angular_velocity` — radians/second

**0.0** disables limiting by default to retain existing project behavior.
Positive values limit the magnitude of the dynamic rigid body's physical
angular velocity after force/torque integration and again after contact
and joint impulses, before updating its transform. The 2D clamp keeps
the sign; the 3D clamp keeps the rotation axis.

Static and kinematic bodies are exempt. Bias angular velocity from
penetration correction is also excluded, so the speed cap does not weaken
position recovery. Gyroscopic integration in 3D runs before the clamp.
The 3D implementation shares the overflow-safe vector magnitude logic
already used by the optional maximum linear speed feature.

The ProjectSettings setting is captured when a physics space is created,
consistent with other GodotPhysics tuning options. It does not change
existing spaces, Jolt, or other third-party physics backends. No additional
per-body/contact memory is required.

Regression coverage:
- C++: `tests/servers/test_godot_physics_angular_velocity_cap.cpp` (build with `tests=yes`)
- Python: `python3 -m unittest tests/stress/test_physics_angular_velocity_cap.py`
- Integration: `godot --headless --path tests/stress --script res://physics_max_angular_velocity_regression.gd`

Large connected islands with high angular velocities should still be
benchmarked under actual load; this guard is not a replacement for CCD,
stable mass ratios or solver convergence tuning.
