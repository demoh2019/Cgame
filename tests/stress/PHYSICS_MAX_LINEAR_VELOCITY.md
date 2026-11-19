# GodotPhysics 2D/3D: maximum dynamic linear speed

Rapier exposes a maximum linear velocity for stability and CCD efficacy.
Cgame adds a disabled-by-default equivalent for the built-in GodotPhysics
backend. It does not change Jolt.

- `physics/2d/solver/max_linear_velocity`: pixels per second
- `physics/3d/solver/max_linear_velocity`: meters per second

Default `0.0` means **unlimited** for backwards compatibility.
A positive setting clamps rigid-body physical linear speed after force
integration (before CCD shape inflation) and again after solver impulses,
before updating the body's position.

Static and kinematic bodies are excluded. Positional bias velocity and
angular velocity are not capped, and this does not replace CCD.

The cap is read on physics-space creation and does not update existing
spaces until they are recreated. Velocities under the cap use a single
squared-length comparison without a square root; disabled speed cap
is a very short fast path. No new per-body or per-contact state.

Regression tests:
- C++: `tests/servers/test_godot_physics_linear_velocity_cap.cpp`
- Python: `python3 -m unittest tests/stress/test_physics_linear_velocity_cap.py`
- Headless: `godot --headless --path tests/stress --script res://physics_max_linear_velocity_regression.gd`

Benchmarks and full native runtime testing are still required before
recommending a nonzero default in production.

When a finite velocity is so large that its squared magnitude overflows
in single-precision builds, the helper uses a scaled-vector fallback to
still enforce the limit without producing NaNs. Normal-sized velocities
retain the original cheap comparison path.
