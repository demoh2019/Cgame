# Two independent reinforcing fiber families in tetra FEM

Experimental biaxial / orthotropic **tension-only fiber reinforcement**
for Cgame's built-in Godot Physics 3D SoftBody3D tetra FEM.

Tissues such as arterial walls and annulus fibrosus, as well as woven
composites, can require two distinct material fiber directions. The
Holzapfel–Gasser–Ogden (HGO) continuum material family is an
inspiration, but Cgame presently uses **two independent unilateral
XPBD fiber constraints** rather than HGO's exponential hyperelastic
energy or a calibrated stress model. No external engine code copied.

## Configure (Project Settings / Physics / 3D / Solver)

Existing:
- `soft_body_tetra_fem_compliance > 0` to enable FEM and tetra cooking.
- `soft_body_tetra_fiber_compliance` and `soft_body_tetra_fiber_axis`
  for family 1 (optional; may be zero/disabled).
- `soft_body_tetra_fiber_plastic_*` for optional family 1 plastic creep.
- `soft_body_tetra_damage_rate` for scalar damage, if desired.

New independent family 2 parameters:
- `soft_body_tetra_fiber_secondary_compliance`: **0 by default**,
  disabled; a positive value enables a second local tensile
  reinforcement row. Lower means stiffer.
- `soft_body_tetra_fiber_secondary_axis`: default `(0,1,0)` in the
  undeformed material frame. Nonzero, finite axes are normalized by
  the existing exact-fiber solver; oblique families are supported.
- `soft_body_tetra_fiber_secondary_plastic_yield_ratio`: default 0.15.
- `soft_body_tetra_fiber_secondary_plastic_creep_rate`: **0**,
  plastic remodeling disabled. Positive rate enables its own
  permanent rest stretch history, independent of family 1.
- `soft_body_tetra_fiber_secondary_plastic_max_stretch`: default 3,
  clipped to [1,16] to cap irreversible stretching.

The second family works even when the first family's compliance is 0,
provided tetra FEM itself is active and the mesh can be cooked.
Inverted/invalid elements reject fiber updates transactionally.

## Material model and state

For each tetra with current deformation gradient `F=Ds*inv(Dm)`,
the two original material unit axes `a0` and `b0` map to stretches:

```
s1 = |F*a0|               s2 = |F*b0|
C1 = sqrt(V0)*(r1-s1)     C2 = sqrt(V0)*(r2-s2)
lambda1 >= 0             lambda2 >= 0
```

Each unilateral XPBD constraint resists **only tensile overstretch**.
The two multipliers have separate per-tetra memory for each physics
frame. No coupling of their active tension multipliers, and pinned
vertices stay pinned. The existing helper computes exact mass-weighted
gradients with positive-element Jacobian guards and backtracking.

If irreversible damage D is active, **both** families use the same
local compliance reduction `alpha_effective=alpha/(1-D)`, but each
has its own independent axis, alpha and plastic rest stretch.

Each plastic rest stretch `r_i>=1` grows only when the corresponding
fiber exceeds its **own** tensile yield. Plastic history is updated
once on predicted positions before elastic projection; it survives
between frames and resets on mesh recreation or disabling its creep.
With secondary compliance or creep disabled, the relevant buffers are
absent and no secondary solver pass runs.

## Verification

- `tests/servers/test_physics_fem_tetra_dual_fiber.cpp`:
  7 native C++ cases: independent axial constraints, secondary-only
  reinforcement, oblique axes and momentum, rigid rotation,
  independent plastic creep, shared scalar damage, invalid states.
- `tests/stress/test_physics_fem_tetra_dual_fiber.py`:
  12,000 independent seeded numerical reference scenarios covering
  biaxial correction, objective material axes, uncoupled plastic creep,
  damage softening and source/lifecycle contracts.
- `.github/workflows/physics-fem-dual-fiber.yml`:
  focused Python CI.

This is **not a full HGO/GOH constitutive model**: there is no fiber
dispersion, exponential fiber energy, multiple cross-family couplings,
fatigue rupture of individual fibers or thermomechanical remodelling.
The full C++ build, physical scene simulation and performance profiling
remain necessary before treating this experimental mode as production
ready. The Jolt backend is not changed.
