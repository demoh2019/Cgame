# Predictive density-pressure for Cgame's experimental native PBF fluid

## Motivation — what DFSPH has and the current PBF lacks

Full DFSPH (Bender & Koschier, 2015) uses a density-pressure solve
**and** a separate divergence-pressure solve. The initial native Cgame
PBF solver (#680) already projects particle positions. PR #700 adds
a velocity-divergence correction *after* advection, but a dense
stationary fluid can still contain density error even when velocity
divergence is zero.

This milestone adds an optional predictive SPH **density-pressure
velocity stage before advection**, followed by the existing PBF
position solver and optional divergence correction. Its pressure
prediction is closer to the density side of DFSPH, but it is not
the full DFSPH algorithm, which uses consistent implicit pressure
solvers, mass-weighted boundary particles and iterative density/
divergence constraints throughout the timestep.

References:
- Bender & Koschier, Divergence-Free Smoothed Particle Hydrodynamics:
  https://animation.rwth-aachen.de/media/papers/2015-SCA-DFSPH.pdf
- SPlisHSPlasH, native pressure solver catalog and DFSPH:
  https://splishsplash.physics-simulation.org/features/
- SPlisHSPlasH, implementing a pressure solver:
  https://splishsplash.readthedocs.io/en/latest/creating_pressure.html

The Cgame solver implementation is original code.

## Equations

At each particle's **current** position x_i and trial velocity
u_i = v_i + dt*g, compute density and its discrete time derivative
with the existing compact-support poly6 kernel:

    rho_i = m * sum_j W(x_i - x_j)
    rho_dot_i = m * sum_j (u_i-u_j) . grad_i W(x_i-x_j)
    rho_adv_i = max(rho_i + dt*rho_dot_i, 0)

Only positive forecast density excess is constrained:

    E_i = max(rho_adv_i / rho0 - 1, 0)
    C_rate_i = E_i / dt

The velocity Jacobian of this **rate-form** constraint is the same
as the existing velocity-divergence projector:

    A_i = sum_j |(m/rho0)*grad_i W_ij|^2
        + |sum_j (m/rho0)*grad_i W_ij|^2
    lambda_i = -C_rate_i/(A_i+1e-6)

Then simultaneously correct all trial velocities:

    delta_u_i = (m/rho0)*sum_j (lambda_i+lambda_j)*grad_i W_ij
    u_i(next) = u_i + clamp_length(relaxation*delta_u_i, max_delta_v)

The pressure-Jacobi loop recomputes rho_dot and rho_adv using updated
velocities, while **rho_i and the Jacobian stay fixed** since positions
do not change. It stops after at most the configured iterations or
when average positive E_i <= tolerance. Predicted positions for the
existing PBF solve are then x_i + dt*u_i(corrected).

For a compressed cloud at rest, rho_dot is zero but E_i remains
positive if rho_i exceeds rho0: this generates outward trial pressure
velocity, unlike the separate velocity-divergence-only projection.

## Engine integration

Original helper: servers/physics_pbf_density_pressure_3d.h.
Native scene node: scene/3d/physics/pbf_particle_fluid_3d.{h,cpp}.

The full step order is:

1. Optional predictive density pressure before advection.
2. Advance predicted particle positions.
3. Existing PBF positional density projection (always).
4. Existing optional rigid contacts and AABB boundaries.
5. XSPH viscosity smoothing.
6. Optional vorticity confinement.
7. Optional divergence velocity projection.

The new predictor reuses the existing deterministic sorted-cell
search (27 neighboring cells, at most 128 accepted neighbors per
particle) and adds four persistent arrays: trial velocities,
simultaneous corrections, Lagrange multipliers and cached Jacobian
denominators. They resize only when the particle count changes.
There are no dynamic allocations within the new pressure iterations.

Maximum accepted pairs per substep:
(2*iterations + 2)*particles*128 (setup, two scans per iteration,
final residual). The global maximum remains 2048 particles.

### Script API and defaults

    fluid.density_pressure_iterations = 8            # default 0 (off)
    fluid.density_pressure_tolerance = 0.002          # 0.2% rho0
    fluid.density_pressure_relaxation = 0.8           # (0,1]
    fluid.density_pressure_max_velocity_change = 0.15 # m/s / iter
    fluid.get_average_predicted_density_error()      # fraction
    fluid.get_last_density_pressure_iterations()     # 0..12
    fluid.get_last_density_pressure_neighbor_evaluations()

The solver is **disabled by default**. When disabled, the original
velocity/position arithmetic and neighbor search remain unchanged.
Enabling it is entirely opt-in on PBFParticleFluid3D.

In demo/physics_lab, key **H** toggles predictive density pressure and
displays its relative forecast density error. The existing keys G
(divergence after advection), V (vorticity), P (rigid coupling),
O (stir), U (refill) and I (pause) remain independent.

## Verification

Independent numerical Python all-pairs reference:

    python3 -m unittest discover -s tests/stress \
      -p test_physics_pbf_density_pressure_3d.py -v

It covers a stationary 125-particle compressed cloud, incoming flow,
3000 random pair-rate signs, no negative pressure at free surfaces,
individual speed caps, pairwise momentum when caps are not saturated,
identical-seed determinism, and C++/CI/source wiring.

An independent NumPy prototype of the same mathematical equations
(with all-pairs neighbors) evaluated 125 particles on a 0.175m
lattice, h=0.42m, m=6, rho0=1000, dt=1/60s, relaxation 0.8,
max change 0.15m/s/iteration:

| Iteration | Mean positive predicted density error, rest static |
|---:|---:|
| 0 | 2.3937% |
| 2 | 1.4927% |
| 4 | 0.5954% |
| 6 | 0.0143% |
| 8 | 0.0019% |

This is **an independent numerical model**, not measured native
Cgame behavior. The finite-precision solver and capped neighbors
may differ.

Standalone compile **of the actual new C++ helper**, float32 and
float64, with only lightweight Godot math stubs:

    for precision in float double; do
      flags=""
      [ "$precision" != double ] || flags="-DCGAME_USE_DOUBLE"
      g++ -std=c++17 -O2 -Wall -Wextra -Werror $flags \
        -Itests/stress/physics_pbf_cpp_stubs -I. \
        tests/stress/test_physics_pbf_density_pressure_compiler.cpp \
        -o "/tmp/pbf_density_pressure_$precision"
      "/tmp/pbf_density_pressure_$precision"
    done

Native doctests (8 new C++ test cases):

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
      --test-case="*[PhysicsPBFDensityPressure]*" --success=true --no-colors

Headless native test with three identical 125-particle fluids,
independent brute-force initial forecast, deterministic replica,
and multi-step finite-state soak:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress \
      --script res://physics_pbf_density_pressure_3d_regression.gd

The dedicated CI file .github/workflows/physics-pbf-density-pressure.yml
runs Python contracts, standalone float/double compilation, then a
full native Godot editor build, C++ doctests, headless scenes and
a pressure-enabled vs pressure-disabled stress comparison.

### CPU and memory baseline

    python3 tests/stress/run.py \
      --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
      --preset smoke --render-mode headless \
      --case physics_pbf_density_pressure_3d_disabled,physics_pbf_density_pressure_3d_enabled \
      --scale 4 --frames 120 --repeats 3 \
      --output pbf-predictive-density-pressure-stress.json

Both workloads run an equally active fluid. The only difference is
the new pressure stage. The harness records physics processing
time, frame p95, process resource use, max density error,
actual pressure iterations and neighbor visits, for 80–2048 particles.

## Important limitations and dependencies

- **Stacked PR:** This feature builds on #700, which builds on #693
  (vorticity), which builds on draft #680 (native PBF). Do not merge
  straight to develop without those dependencies.
- The predictor uses first-order SPH continuity, a fixed-position
  Jacobian and capped Jacobi velocities followed by the PBF position
  solve. It is NOT full DFSPH with two pressure Poisson solvers or
  pressure warm-start, and it does NOT guarantee exact incompressibility.
- Boundaries use the original AABB and optional ray impacts, not
  pressure boundary particles; no continuous two-way fluid-solid
  pressure transfer is introduced.
- A 128-neighbor cap, artificial correction clamp and unilateral
  free surfaces can break pairwise symmetry and exact conservation
  under overload. The clamp reduces instability but can leave pressure
  error after the final iteration.
- Additional neighbor passes are CPU-heavy at 2048 particles; native
  benchmarks and stress must pass before production use.

**Do not merge while native CI is unverified.** All claims of error
reduction in this document refer to the independent numerical model,
not a Godot engine executable.
