# Jolt soft-body wind: constant-attenuation fast path and bounded per-body scratch

Cgame applies wind to soft-body cloth by walking every face and every wind
Area3D affecting the body. For each face/area pair, the previous code
performed a centroid/projection calculation and `Math::pow()` even when
`AREA_PARAM_WIND_ATTENUATION_FACTOR` was its common **zero** default.
Since `pow(max(projection, 1), -0) == 1`, this repeated expensive work had
no physical effect.

It also allocated a fresh temporary `LocalVector<JoltArea3D *>` for wind
areas every physics step on every soft body touched by wind.

## Changes

- Detect whether any active wind area uses nonzero distance attenuation.
  If none do, skip the per-triangle centroid construction.
- For each individual wind area with zero attenuation, use a factor of
  exactly `1` and skip projection and `Math::pow()`, even if another
  area's attenuation is nonzero.
- Preserve the original `Math::pow(max(projection, 1), -factor)` calculation
  and wind magnitude, area-priority order, triangle normals, gravity
  overrides, and per-particle impulse distribution for nonzero attenuation.
- Reuse a `LocalVector<JoltArea3D *>` scratch list owned by each soft
  body. No shared scratch or global lock; the body's `pre_step` owns it.
  Clear references after every step so removed areas are never retained.
- Retain ordinary scratch capacity and free allocations after a
  large-to-small drop when the capacity exceeds
  `max(64, 4 * current_wind_area_count)`. A sustained dense wind scene
  keeps its working capacity without reallocating every frame.

The optimized path uses the exact physical result for zero attenuation;
Jolt's XPBD solver and soft body constraint order are untouched.

## Validation

```sh
python3 -m unittest tests/stress/test_jolt_softbody_wind_fastpath.py -v

./bin/godot.linuxbsd.editor.dev.x86_64 --headless --path tests/stress \
    --script res://physics_jolt_softbody_wind_fastpath_regression.gd
```

The Python reference model compares attenuation before/after the change
for **10,000 seeded random** positions, sources, directions and exponents,
including many zero-attentuation cases, and checks the scratch-retention
thresholds.

The native GDScript creates a 16×16 cloth mesh (450 triangles), activates
two Jolt Area3D wind zones and tests a constant-wind phase, a phase with
mixed attenuation, a calm phase, and resumed constant wind. It reports
vertex movement and wall time, checks finite positions/bounds, and rejects
failure to move under wind. The CI job explicitly enables Jolt, checks
GDScript syntax, executes the fixture and archives its output.

Before claiming performance gains, compare CPU time in
`JoltSoftBody3D::_apply_environmental_forces` and process RSS on the same
host/scene and compiler flags, including phases with 0, 1, and multiple
wind areas. The mathematical work reduction is established by inspection,
but **native runtime and FPS/RAM gains require completed CI/benchmarks**.

Jolt documents that soft bodies are made of particles and constraint
data. This patch leaves those constraints unchanged and optimizes only
Godot-specific external wind force preparation.
