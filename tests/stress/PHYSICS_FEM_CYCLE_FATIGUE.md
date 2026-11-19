# Volumetric FEM cycle-dependent fatigue — principal strain and Miner damage

This introduces an optional **cyclic fatigue material weakening** model
for each tetrahedral element in the built-in GodotPhysics3D SoftBody3D
FEM solver. It complements — and shares the very same irreversible scalar
damage `D` as — existing *static overload* damage. It is inspired by
cyclic-damage mechanics in FEBio and simplified Palmgren–Miner fatigue.

The fatigue system can weaken a soft body under many **repeated sub-failure
loads**, even if no individual loading event exceeds the static overload
yield. A constant load or pure rigid-body motion causes **no fatigue
cycles**. This is not mesh splitting, rainflow/ASTM cycle counting, or a
calibrated fatigue-life prediction; multi-level variable amplitude
loading needs more sophisticated rainflow and S-N material calibration.

## Project Settings

```ini
physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001

physics/3d/solver/soft_body_tetra_fatigue_reference_cycles = 1000
physics/3d/solver/soft_body_tetra_fatigue_endurance_amplitude = 0.05
physics/3d/solver/soft_body_tetra_fatigue_reference_amplitude = 0.30
physics/3d/solver/soft_body_tetra_fatigue_exponent = 3.0
physics/3d/solver/soft_body_tetra_fatigue_reversal_deadband = 0.002
```

- `reference_cycles = 0` **(default)** completely disables cyclic fatigue.
- `endurance_amplitude`: cycles of principal logarithmic half-range at or
  below this amplitude cause no additional damage.
- `reference_amplitude`: principal-log-strain cycle half-range whose
  excess above endurance corresponds to the `reference_cycles` design
  count. Must exceed the endurance amplitude.
- `reference_cycles`: positive, approximate number of detected cycles
  for D to grow by 1 at the reference amplitude, before the cap at 0.95.
- `exponent`: Basquin-like amplitude sensitivity (range 1..10).
- `reversal_deadband`: small changes in signed principal strain below
  this threshold do not switch the turning-point detector. Helps suppress
  numerical jitter causing false fatigue cycles.

## Physics, limitations and tuning

For each tetrahedron, calculate `F=Ds*inverse(Dm)`, then
`sigma_i=sqrt(eig(F^T F))`. Select the principal logarithmic
strain `e_i=ln(sigma_i)` of greatest absolute value, preserving its
sign (tension positive, compression negative). This gives a
**rotation/translation invariant scalar 3D fatigue history**, not
a per-edge distance measurement.

A compact (O(1)) incremental extremum detector remembers consecutive
strain reversals. When *peak_previous -> valley -> peak_new* occurs,
use the amplitude of the overlapping peak/valley excursion:

```text
A = max(0, min(peak_previous,peak_new)-valley)/2
A_normalized = max(0, A-endurance) / (reference-endurance)
D_next = min(0.95, D_old + A_normalized^exponent / reference_cycles)
```

This is a deliberate **small-memory approximation**, not the standard
ASTM E1049 rainflow method. It counts only fully identified nested
peak-valley-peak cycles; short sequences and incompletely closed
cycles can be missed. The S-N formula is phenomenological, and the
parameters must be calibrated before any prediction of real fatigue
life.

The cycle sampler runs **once per physics tick on predicted positions**,
before the XPBD solver projects out the peak strain. The separate
static-overload mechanism updates the *same* scalar damage value.
The existing nonzero residual stiffness `1-D >= 0.05` is preserved.

Every existing FEM material and optional local reinforcement reads
this same scalar damage, including Neo-Hookean, Mooney–Rivlin,
Ogden, material fibers and transient SLS/Prony springs. Supports
prevalidated cooked convex and imported explicit tet meshes.

No new state is allocated and no new FEM loop runs when fatigue is
off. Per-element history resets when the mesh/rest tetra topology
is explicitly rebuilt. A disconnected tesselation does not emerge
spontaneously, even at maximum damage.

## Tests

- `tests/servers/test_physics_fem_tetra_cycle_fatigue.cpp`:
  18 native doctest cases for rest, holds, monotone loading, cycle
  counting, Miner damage, endurance, compression, damage saturation,
  deadband, objectivity, shear, winding, inverted tetra, parameter
  rejection and coupling with existing compliance.
- `tests/stress/test_physics_fem_tetra_cycle_fatigue_compiler.cpp`:
  compile/run the real production header in float32 and float64.
- `.github/workflows/physics-fem-cycle-fatigue.yml`: dedicated CI.

Native full Godot engine build, multi-object fatigue stress tests,
rate effects under contact, varying-amplitude/rainflow comparisons,
and fatigue calibration are not verified by these checks.

## Background

- [FEBio reactive fatigue](https://febiosoftware.github.io/febio-docs/user/chapter4/4.7-reactive-fatigue/)
- [Palmgren–Miner accumulation in OpenRainflow](https://openrainflow.readthedocs.io/en/latest/api/damage.html)
