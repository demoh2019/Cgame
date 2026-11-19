# Opt-in corotational shape matching for GodotPhysics3D soft bodies

## Why this feature

Cgame `develop` already has PBD springs plus XPBD stretch, area,
shear, dihedral bending, enclosed surface volume, tether constraints,
plasticity and self collision. **What is still missing** for a
solid-like but surface-mesh-driven deformable object is a mechanism
that stores the *overall rest shape* and resists global shearing or
collapse without requiring hand-authored interior tetrahedralization.

The 2005 Müller–Heidelberger–Teschner–Gross shape-matching model is
appropriate here: it fits a rigid pose to a deforming point cloud,
then softly projects points towards that posed reference shape.

This is **corotational PBD shape matching**, NOT tetrahedral FEM,
not a physically calibrated Young's modulus, and not an XPBD
energy constraint. It complements the existing local constraints.

Primary paper:
https://doi.org/10.1145/1073204.1073216
Freely available paper:
https://cgl.ethz.ch/Downloads/Publications/Papers/2005/Mue05/Mue05.pdf

## Enabling

Select GodotPhysics3D as the physics engine and set

```ini
[physics]
3d/physics_engine="GodotPhysics3D"
3d/solver/soft_body_shape_matching_rate=20.0
```

The property `physics/3d/solver/soft_body_shape_matching_rate`
defaults to **0.0** and is measured in inverse seconds. With zero,
the new code does **no** shape fit, mesh traversal, eigendecomposition
or extra memory allocation. The rate is read once per physics space;
recreate an already-running space to apply a new ProjectSettings value.

Positive rates map to one update per physics step:

```text
fraction = 1 - exp(-rate * delta_time)
position = position + fraction * (rigid_goal - position)
```

For constant deformation this produces comparable relaxation under
different physics step sizes. A rate near 20/s gives ~0.2835 correction
per 60 Hz step; a rate of 0 gives none. It is *not* a stiffness in
newtons/meters or an FEM material coefficient.

## Implementation

The helper `servers/physics_softbody_shape_matching.h` is a
single-header, zero-allocation, O(number of physical particles) solver:

1. Read the existing per-node rest `s` and predicted `x` positions;
   validate every position and inverse mass, compute source/current
   centers in `double`. Every material particle has equal fitting
   weight; pinned particles also contribute to determining the rigid
   pose, but cannot be moved by correction.
2. Form the centered 3×3 covariance
   `H = Σ (x_i - mean(x)) (s_i - mean(s))^T` in double precision.
   Normalize covariance by its largest component for scale resistance.
3. Build Horn's **symmetric 4×4 quaternion matrix** and find the
   largest eigenvector using at most 48 Jacobi rotations. This
   produces a **proper rotation** rather than a reflection and
   handles free translations/rotations without inventing elastic
   force in those modes. On a completely collapsed current shape
   the deterministic identity quaternion restores the reference
   shape instead of producing NaNs.
4. Compute each rigid goal `mean(x) + R * (s_i-mean(s))`.
   Validate all resulting float positions **before modifying any**.
   The second pass commits only for `inverse_mass > 0`, preserving
   exact fixed points. No position/rotation arrays are persisted.
5. Run **once per physics step**, after local stretch/area/shear,
   hinge/volume/tether projections and before self-collision and
   velocity reconstruction. This avoids a costly eigensolve on every
   XPBD inner solver iteration. The existing soft-body normals and
   velocities are updated using the corrected positions as before.

For free equal-mass bodies, centroid fitting leaves translation
unchanged; rigid rotation is likewise a zero-error mode. This global
reference provides shape memory for soft solids and inflatable shells
but may overconstrain freely folding fabric. Keep disabled for cloth
when full folding is desired. A truly local shape-matching cluster
decomposition would be a separate feature.

## Robustness and limitations

- No valid source shape (fewer than four vertices, all rest points
  identical), invalid fraction, negative/non-finite inverse mass or
  non-finite coordinates: **no changes**.
- All-pinned bodies perform no correction. Partial pins act as
  immovable constraints during commit, but contribute to the rigid
  fit like ordinary material particles.
- All-node equal fitting weights reflect Cgame's current identical
  per-particle soft-body mass. This is **not a general heterogeneous
  mass-weighted Procrustes solver**.
- The eigensolver uses only proper rotations (no mirroring).
  A collapsed current configuration uses the identity rotation;
  extremely large world coordinates can lose float32 precision.
- The per-step correction can alter linear/angular momentum when
  pins or external constraints are present. The physics is PBD, not
  energy/impulse-conserving FEM. It can conflict with other constraints
  on severe deformation; small rates and smaller physics steps
  typically behave more smoothly.
- No tetrahedral mesh, stress tensor, Young's modulus, Poisson ratio,
  material fracture, local hexahedral/tetrahedral FEM, or arbitrary
  deformation modes are introduced in this patch.

## Validation

```bash
# Integration contracts
python3 -m unittest discover -s tests/stress -p 'test_physics_softbody_shape_matching.py' -v

# Standalone real header C++ syntax/math smoke, NOT the full engine
g++ -std=c++17 -O2 -Wall -Wextra -Werror -pedantic \
  -Itests/stress/mock_shape_matching -I. \
  tests/stress/physics_softbody_shape_matching_standalone.cpp -o /tmp/cgame-shape
/tmp/cgame-shape

# Build Cgame with tests=yes, then run native tests:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Shape matching leaves rigid translations and rotations unchanged"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Shape matching restores sheared soft solid without pin movement"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Shape matching restores totally collapsed geometry deterministically"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Shape matching preserves proper orientation instead of reflecting shape"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Shape matching respects pins and rejects invalid inputs atomically"
```

The dedicated GitHub Actions job tests GCC and Clang with the actual
header using a standalone test-only Vector3 replacement and 6000 seeded
rigid poses. An independent double-precision numerical reproduction
matched 1000 randomly sampled proper 3D rotations with maximum matrix
entry error ~1.7e-13.

Before merge, compile all of Cgame, run the native suite, run
real solid-like soft-body scenes (spinning ball, pinned cube, crushed
shell), check NaNs/explosions, p50/p95/p99 physics step times and
peak RSS at matched geometry/iterations. Standalone tests and source
contracts do **not** establish correctness of the complete engine.
