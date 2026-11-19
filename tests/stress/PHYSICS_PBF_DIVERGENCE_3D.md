# PBF velocity-divergence correction in Cgame

## Motivation and scope

Cgame already contains native CPU Position Based Fluids (PBF) density
position constraints, XSPH viscosity and optional vorticity confinement.
PBF position projection reduces density compression but can leave a
compressing velocity field, producing unwanted compression next frame.

The DFSPH method by Jan Bender and Dan Koschier solves two related
problems: density error and velocity divergence error. This Cgame
feature takes an **intermediate step**: an optional post-PBF velocity
projection with unilateral SPH density-rate constraints. It does not
replace PBF with a full DFSPH two-pressure Poisson solver.

Sources:

- Bender & Koschier (2015), Divergence-Free SPH:
  https://animation.rwth-aachen.de/media/papers/2015-SCA-DFSPH.pdf
- Bender & Koschier (2017), incompressible viscous DFSPH:
  https://dankoschier.github.io/resources/papers/BK17.pdf
- SPlisHSPlasH pressure solver methods:
  https://splishsplash.physics-simulation.org/features/

This is original code, not a copied external fluid implementation.

## Algorithm

For particle positions p, velocities v, uniform mass m, smoothing
kernel W with gradient g, and target density rho0:

    rho_dot_i = SUM_j m * (v_i - v_j) . grad_i W_ij
    C_i = max(rho_dot_i/rho0, 0)

The positive branch represents compression. The negative branch
(separating free-surface particles) is intentionally unconstrained.

Linearize the constraint with respect to velocities:

    dC_i/dv_j = -(m/rho0) * grad_i W_ij
    dC_i/dv_i = (m/rho0) * SUM_j grad_i W_ij
    denom_i = SUM_j |dC_i/dv_j|^2 + |dC_i/dv_i|^2
    lambda_i = -C_i/(denom_i+1e-6)

Apply simultaneous Jacobi velocity updates:

    dv_i = (m/rho0) SUM_j (lambda_i+lambda_j) * grad_i W_ij
    v_i_next = v_i + bounded(relaxation * dv_i, max_delta_v)

For two approaching particles, dv is directed apart, decreasing
the positive density rate. The position field remains unchanged during
this velocity pass; changes affect subsequent particle prediction.
The pass runs AFTER XSPH and vorticity restoration, so it can
correct their compressive velocity components too.

The main native code is in
servers/physics_pbf_divergence_3d.h (allocation-free helper) and
scene/3d/physics/pbf_particle_fluid_3d.cpp (cell-neighbor Jacobi loops).
A new pair of velocity/multiplier arrays is allocated only when
particle count changes, then reused for all iterations.

## Script and editor API

    fluid.divergence_iterations = 8           # default 0, max 12
    fluid.divergence_tolerance = 0.01         # in 1/s; 0–10
    fluid.divergence_relaxation = 0.8         # (0,1]
    fluid.divergence_max_velocity_change = 0.12  # m/s per iteration
    fluid.get_average_positive_density_rate()
    fluid.get_last_divergence_iterations()
    fluid.get_last_divergence_neighbor_evaluations()

With divergence_iterations=0, no extra grid sort, neighbor traversals
or velocity modifications occur. The adaptive solver stops early if
the mean positive rate is below the configured tolerance.

Each Jacobi iteration performs up to two neighbor traversals per particle
plus one final residual traversal. The strict limit on accepted pairs
per substep is (2*iterations+1)*particles*128, with 2048 particles
maximum. Cell search uses the PBF solver's existing deterministic
27-cell sorted grid and no new per-frame allocation.

In demo/physics_lab, press G to toggle divergence correction and
see the measured compression residual; V independently controls
vorticity, O stirs water, P toggles discrete rigid contacts.

## Independent numerical reference

An independently written brute-force all-pairs SPH/velocity solver
is supplied in tests/stress/test_physics_pbf_divergence_3d.py. It
checks 5000 random approaching/separating pairs, constant velocity
with zero false compression, an inward 125-particle cloud, free-surface
expansion, momentum without saturated caps, deterministic results
and finite correction limits.

For an inward flow v=-2p with 125 particles on a 0.19m lattice,
h=0.42m, mass=6, rest density=1000, relaxation=0.9 and an
individual velocity cap of 0.12m/s per iteration:

| Jacobi iteration | Average positive density rate / rho0 (1/s) |
|---:|---:|
| 0 | 3.3343 |
| 2 | 2.4826 |
| 4 | 1.6302 |
| 6 | 0.7912 |
| 8 | 0.0660 |

These are **reference-model values**, not runtime Cgame measurements.

## Verification and performance

The dedicated physics-pbf-divergence.yml GitHub workflow compiles the
REAL Cgame divergence helper in float32 and float64 with -Werror,
runs Python mathematical tests, builds the entire GodotPhysics3D
editor and executes native C++ doctests and headless integration.

Native doctest filter: [PhysicsPBFDivergence].
Headless regression: tests/stress/physics_pbf_divergence_3d_regression.gd.
The headless scene compares three identical 125-particle clouds:
original PBF, corrected PBF, deterministic corrected replica. The
test computes an independent all-pairs SPH compression residual,
checks a real reduction and validates bounded finite states.

The stress harness has two new, identical active-PBF workloads:
physics_pbf_divergence_3d_disabled and
physics_pbf_divergence_3d_enabled. All other solver settings remain
identical. CPU physics time, frame p95, memory and neighbor/iteration
counters can be recorded up to 2048 particles.

Example command (after building native Cgame):

    python3 tests/stress/run.py --preset smoke \
      --case physics_pbf_divergence_3d_disabled,physics_pbf_divergence_3d_enabled \
      --scale 4 --frames 120 --repeats 3 --output pbf-divergence-stress.json

## Limitations and dependencies

- This change is stacked on experimental PR #693 (vorticity), which
  itself depends on PR #680 (native PBF fluid). Both predecessors
  must be reviewed/landed or the branch retargeted carefully.
- It does NOT implement a full DFSPH pressure solve, exact volume
  preservation, FLIP/APIC, GPU fluids or continuous pressure coupling
  to rigid bodies. It is a bounded *velocity-projection improvement*.
- The 128-neighbor cap can produce asymmetric neighbor lists.
  Individual safety caps and one-sided surface corrections may
  break exact global momentum/energy invariants.
- With an insufficient iteration budget, difficult compression may
  remain after correction. Diagnostics report the FINAL residual.
- Zero iterations is the default and retains previous behavior.

Native CI and benchmarks must pass before considering this feature
ready for production. No full-engine results are claimed yet.
