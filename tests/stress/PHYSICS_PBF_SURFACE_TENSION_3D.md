# Native PBF surface cohesion and curvature — Cgame GodotPhysics3D

## Gap relative to mature SPH engines

Cgame's experimental `PBFParticleFluid3D` already contains a density
position solver, XSPH viscosity, opt-in vortex confinement, a
density-predictive pressure stage and velocity-divergence correction.
It does not yet model the free liquid surface's tendency to minimize
area and form coherent droplets.

SPlisHSPlasH provides a number of surface tension choices, from
Becker-Teschner through Akinci and implicit methods. The two-component
approach combines a **short-range repulsive / long-range cohesive
radial kernel** with a **difference of SPH color-field normals**
(approximate curvature). This Cgame patch is an original, opt-in
explicit bounded implementation following these published principles.

References (no external implementation copied):

- SPlisHSPlasH surface tension feature list:
  https://splishsplash.physics-simulation.org/features/
- Akinci, Akinci & Teschner (2013), Versatile Surface Tension and
  Adhesion for SPH Fluids, ACM Transactions on Graphics 32(6).
- M. Huber et al. (2015), Evaluation of Surface Tension Models for
  SPH-Based Fluid Animations:
  https://diglib.eg.org/server/api/core/bitstreams/3c45e880-9a83-40d2-be31-72ba8e85191c/content
- SPlisHSPlasH surface tension scene settings:
  https://splishsplash.readthedocs.io/en/latest/file_format.html

## New SPH surface algorithm

`servers/physics_pbf_surface_tension_3d.h` implements three independent,
allocation-free primitives: cohesion kernel, color-field normals and a
pairwise bounded velocity change. The native scene node drives them
using its preexisting deterministic sorted 27-cell neighbor grid.

For current post-PBF particle positions x_i and rest density rho0:

1. Compute rho_i = m * SUM_j W(x_i-x_j) at final corrected positions.
2. Compute the dimensionless SPH color normal:

       n_i = h * SUM_j (m / max(rho_j, 0.1*rho0)) * grad W(x_i-x_j)

3. For every accepted unordered pair (i,j), **exactly once**, compute:

       K_ij = min(4, 2*rho0 / (rho_i+rho_j))
       r = |x_i-x_j|
       a_ij = -K_ij * [
           cohesion * m * C(r,h) * (x_i-x_j)/r
         + curvature * (n_i-n_j)
       ]
       dv_ij = dt*a_ij, length-capped by max_pair_velocity_change
       dv_i += dv_ij
       dv_j -= dv_ij

The custom radial cohesion kernel is zero outside 0<r<h:

       C(r,h) = 32/(pi*h^9) * [
           (h-r)^3*r^3           for h/2 < r < h
           2*(h-r)^3*r^3-h^6/64 for 0 < r <= h/2
       ]

C(r,h) becomes **negative at very close distances**, producing
repulsion and reducing artificial clumping. Its positive outer
branch generates cohesion and a net force toward neighbors near
the free surface. The curvature term reduces color-normal
discontinuities around thin, curved interfaces.

### Pairwise conservation

The force stage adds **exactly opposite velocity changes** for
each accepted equal-mass pair, including when the neighbor cap
prevents another pair from being visited. Therefore, in
isolation the stage preserves total **linear momentum** (to
floating-point accumulation precision).

It does **not** guarantee angular momentum conservation:
curvature impulses can be noncentral. Nor does it conserve global
kinetic energy, as this is an explicit visual SPH surface model,
not an implicit surface-energy minimizer. Later viscosity, PBF
positional constraints, external boundaries and pressure may
also change energy and momentum.

All pair impulses are computed before changing any velocities.
If any accumulated velocity becomes nonfinite, the **entire batch**
is rejected, rather than applying only one half of a pair.

## Native integration and controls

After PBF advection, position constraints, rigid-body contacts
and XSPH smoothing, the new surface stage runs before vortex
confinement and divergence pressure correction.

New GDScript/editor properties (all opt-in):

    fluid.surface_cohesion = 0.0    # range 0..2; zero by default
    fluid.surface_curvature = 0.0   # range 0..2; zero by default
    fluid.surface_max_pair_velocity_change = 0.005 # m/s, 0.0001..0.05

New diagnostics:

    fluid.get_last_surface_tension_pairs()
    fluid.get_last_surface_tension_neighbor_evaluations()
    fluid.get_mean_surface_normal_magnitude()

The **surface stage is completely disabled** when both cohesion
and curvature are zero. It performs no grid sort, extra neighbor
visits or CPU forces, and has **no scratch allocations while off**.
Three arrays for densities, color normals and accumulated changes
are allocated on enabling one of the coefficients, and cleared
when both are set back to zero. This also supports live editor/
GDScript toggling without stale arrays.

At most three 128-neighbor passes per particle are performed
each enabled substep (density, normals, single-visit unordered
pairs). This is bounded by 3*2048*128 accepted neighbor visits
plus cell binary searches and sorting. The per-pair velocity
cap bounds each **pair**, not the sum over all neighbors: a
particle can accumulate contributions from at most 128 accepted
pairs. Parameter values are deliberately bounded. This
post-process is for moderate 80-2048 particle CPU liquids,
not a GPU million-particle simulation.

The numerical coefficients above are **tunable acceleration
strengths**, not measured physical surface tension in N/m.
They depend on SPH mass, spacing and smoothing radius and
must be calibrated per scene; do not claim that .06
corresponds to the N/m surface tension of pure water.

Physics Lab: visit the native water station via TAB. Press
**J** to enable the paired cohesion (0.06) and curvature
(0.025) stage. Its label shows pair count and mean surface
normal magnitude. Existing keys H (predictive pressure),
G (velocity divergence), V (vortices), P (rigid contacts),
O (stir), U (refill) and I (pause) are independent.

## Tests and standalone compilation

- Eight native C++ doctests in
  `tests/servers/test_physics_pbf_surface_tension_3d.cpp`:
  kernel compact support and near-field repulsion, long-range
  attraction, order-symmetric Newton pairs, curvature sign,
  per-pair clamping, bad input rejection, active/disabled
  liquid momentum and deterministic reseed/toggling.
- Independent all-pairs Python solver with **3000 random
  kernel evaluations**, **3000 random action/reaction/cap checks**,
  two-particle attraction/repulsion, curvature, symmetric
  125-particle droplet and noisy 125-particle cloud:
  
      python3 -m unittest discover -s tests/stress \
        -p test_physics_pbf_surface_tension_3d.py -v

- Standalone compile of the **actual native header** in both
  float32/float64 using only isolated Vector3 math stubs:

      for precision in float double; do
        flags=""
        [ "$precision" != double ] || flags="-DCGAME_USE_DOUBLE"
        g++ -std=c++17 -O2 -Wall -Wextra -Werror $flags \
          -Itests/stress/physics_pbf_cpp_stubs -I. \
          tests/stress/test_physics_pbf_surface_tension_compiler.cpp \
          -o "/tmp/pbf_surface_tension_$precision"
        "/tmp/pbf_surface_tension_$precision"
      done

- Godot native doctest filter: `*[PhysicsPBFSurface]*`.
- Headless real-fluid regression:
  `tests/stress/physics_pbf_surface_tension_3d_regression.gd`
  compares **three identically initialized 125-particle
  fluids** (original off, surface on, enabled deterministic
  replica), validates pair counters, no accidental default
  physics cost, equal-and-opposite momentum for the first
  step, deterministic soak, finite positions, safe toggling.
- Native full engine CI and headless demo syntax tests:
  `.github/workflows/physics-pbf-surface-tension.yml`,
  plus integration in `whole-engine-stress.yml`.

Independent NumPy all-pairs reference for a 125-particle
0.19m lattice, h=0.42m, mass 6, rest density 1000,
cohesion=0.06, curvature=0.025 and 1/60s substep:

| Metric | Reference value |
|---|---:|
| Accepted unordered interaction pairs | 1261 |
| Maximum color-normal magnitude | 1.493 |
| Total sum of per-particle speed changes | 2.960 m/s |
| Maximum one-particle accumulated change | 0.030 m/s |
| Total vector change residual | ~8.2e-17 m/s |

These numbers describe the independent mathematical reference,
**not a measured Cgame engine run**.

## Headless CPU and memory regression

The existing stress harness registers two fully active PBF
workloads identical except for surface forces:

    python3 tests/stress/run.py \
      --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
      --preset smoke --render-mode headless \
      --case physics_pbf_surface_3d_disabled,physics_pbf_surface_3d_enabled \
      --scale 4 --frames 120 --repeats 3 \
      --output pbf-surface-stress.json

It records frame p95, physics CPU time, RSS, number of
accepted pair impulses, total neighbor visits and average
normal magnitude for particle counts up to 2048.

## Dependencies and limits

**This is stacked on draft PR #706**, itself stacked on
#700 (divergence) -> #693 (vorticity) -> #680 (native PBF).
Merge or rebase the chain sequentially; do not introduce
surface tension directly into develop without its dependencies.

The surface tension implementation is experimental: no
wall adhesion/wetting contact angle, no air-liquid two-phase
surface model, no implicit surface-energy solver, no mesh
surface reconstruction and no GPU processing. It makes no
claim to exact physical material calibration, global angular
momentum or kinetic-energy conservation. Negative cohesion
values and uncontrolled per-pair acceleration are rejected.

**Do not merge until** the standalone float/double C++
compiler, Python reference, full native Godot build,
GDScript headless scene and 2048-particle CPU/RSS stress
checks pass. No successful native CI is claimed without
actual workflow results.
