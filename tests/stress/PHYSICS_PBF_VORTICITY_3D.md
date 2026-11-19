# PBF dynamic-fluid vorticity confinement — Cgame GodotPhysics3D

## Gap in the current fluid solver

Cgame's opt-in native `PBFParticleFluid3D` already implements
one-sided density constraints, XSPH viscosity, artificial pressure,
spatial neighbor search and optional rigid contact impulses. However,
every density projection and XSPH filter removes some rotational
kinetic energy. Consequently, splashes and swirls look progressively
over-damped, even with physically relevant agitation.

The original PBF paper explicitly adds **vorticity confinement**
to restore rotational flow lost to numerical damping:

- Macklin & Müller (2013), *Position Based Fluids*:
  https://mmacklin.com/pbf_sig_preprint.pdf
- SPlisHSPlasH methods and vorticity references:
  https://splishsplash.physics-simulation.org/features/
- Stanford PBF programming assignment:
  https://graphics.stanford.edu/courses/cs348c-21-winter/PA1_PBF2016/index.html

This patch uses original Cgame code; no external physics source is
copied into Cgame.

## Implemented native algorithm

A new standalone, allocation-free kernel in
`servers/physics_pbf_vorticity_3d.h` is combined with a three-pass
velocity post-process in
`scene/3d/physics/pbf_particle_fluid_3d.cpp`.

All quantities are evaluated at **final corrected particle positions**
and **post-XSPH velocities**, using the same compactly supported
3D poly6 kernel and the same deterministic cell search as the PBF
density constraint.

1. Refresh density `rho_j` after the density projection and rigid
   contacts, so `m/rho_j` is the correct neighbor volume.
2. Evaluate SPH velocity curl:

   ```text
   omega_i = sum_j (m/rho_j) * [ grad_i W(pi-pj,h) cross (vj-vi) ]
   ```

   The cross-product order is deliberate: positive rotation around
   world +Z yields positive `omega_z`.
3. Evaluate the gradient of the **curl magnitude**:

   ```text
   eta_i = sum_j (m/rho_j) * (|omega_j|-|omega_i|) * grad_i W(pi-pj,h)
   N_i = eta_i/|eta_i|
   ```

   If `eta_i` is tiny or the curl is zero, the contribution is zero.
4. Add an optional velocity increment:

   ```text
   delta_vi = dt * vortex_strength * (N_i cross omega_i)
   |delta_vi| <= vortex_max_velocity_change
   vi(next) = vi + delta_vi
   ```

   Strength is in m/s. It controls **visual energy restoration**;
   vorticity confinement intentionally injects energy and is *not*
   a conservative Navier–Stokes turbulence or viscosity model.

Every correction is written to a separate preallocated buffer before
any velocity is modified, avoiding update-order dependence. Strong
vortices are capped at 0.12 m/s per substep by default. All outputs
are checked for finite values; invalid and degenerate gradients yield
zero corrections.

## CPU/runtime controls

The new properties on `PBFParticleFluid3D` are:

- `vorticity_confinement = 0.0` (m/s; allowed 0–5): disabled by default;
  a strength of `0.9` is a reasonable demo test, not a universal
  physically calibrated parameter.
- `vorticity_max_velocity_change = 0.12` (m/s per substep; allowed
  positive up to 2): numerically limits rotational energy injection.
- `get_average_vorticity()`: average magnitude of curl in s⁻¹.
- `get_last_vorticity_neighbor_evaluations()`: actual neighbor visits
  from the density refresh, curl and magnitude-gradient passes.

The three new particle buffers are resized only when the particle set
is initialized or replaced. A default-disabled fluid performs no new
neighbor traversals and no density-grid rebuild for vorticity.

Each enabled substep performs up to **three extra bounded neighbor
queries per particle**, with 128 neighbors per query, so the additional
work is at most `3*particles*128` accepted pairs plus the integer-grid
sort and up to 27 binary searches per particle per pass. The
post-process retains the 2048-particle cap of the original solver.

In the interactive Physics Lab, `Tab` visits the PBF tank at
`(-28,0,-11)`. Press `O` to stir and `V` to toggle the vortex
restoration without replacing the particle state. The label reports
the mean curl measured by the native solver. `I` pauses and `P`
independently enables the costly rigid-body collision coupling.

## Numerical/native verification

Standalone C++ helper compiler smoke in both float32 and float64:

```bash
for precision in float double; do
  flags=""
  if [ "$precision" = double ]; then flags="-DCGAME_USE_DOUBLE"; fi
  g++ -std=c++17 -O2 -Wall -Wextra -Werror $flags \
    -Itests/stress/physics_pbf_cpp_stubs -I. \
    tests/stress/test_physics_pbf_vorticity_compiler.cpp \
    -o "/tmp/physics_pbf_vorticity_$precision"
  "/tmp/physics_pbf_vorticity_$precision"
done
```

Independent Python reference: **4000 random pair-curl tests**, uniform
velocity (exact zero curl), clockwise/counterclockwise solid-body
rotation (opposite signed curl), spatially concentrated Gaussian
vortex, random extreme-curl caps and a 125-particle shear field:

```bash
python3 -m unittest discover -s tests/stress \
  -p test_physics_pbf_vorticity_3d.py -v
```

Native Godot C++ doctests (7 cases):

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="*[PhysicsPBFVorticity]*" \
  --success=true --no-colors
```

Actual native class simulation, headless, without artificial background
rendering:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress --script res://physics_pbf_vorticity_3d_regression.gd
```

That scene runs **three identically seeded 125-particle clouds**, all
with the same swirl impulse: original vorticity disabled, enabled, and
a second enabled replica. It checks real nonzero curl and velocity
differences, deterministic replicas, finite positions, box limits,
neighbor caps and proper reset when particles are cleared.

The dedicated workflow
`.github/workflows/physics-pbf-vorticity.yml` compiles the **real
helper** in both precision modes and runs the independent reference.
The full `.github/workflows/whole-engine-stress.yml` adds native
Godot doctests and the actual headless GDScript scene.

### On/off performance and memory comparison

The existing PBF stress runner is reused, with two new cases that
both run the same density solver and the same number of particles:

```bash
python3 tests/stress/run.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --preset smoke --render-mode headless \
  --case physics_pbf_vorticity_3d_disabled,physics_pbf_vorticity_3d_enabled \
  --scale 4 --frames 120 --repeats 3 \
  --output physics-pbf-vorticity-stress.json
```

Use `--scale 1` through `--scale 8` for progressively larger
clouds, up to 2048 particles. The JSON records frame p95, physics
process cost, peak average curl and vorticity neighbor checks, and
the process wrapper tracks memory. **No measurements are claimed**
until these tests run on an actual native build.

## Limitations and dependencies

- This patch is **stacked onto draft PR #680**. Merge/rebase the
  underlying native PBF scene node before treating the vorticity PR
  as independently mergeable into `develop`.
- This does **not** implement implicit SPH viscosity, DFSPH,
  artificial boundary vorticity, multiphase fluids, turbulence
  cascade, true surface-tension curvature or GPU acceleration.
- Vorticity confinement can inject energy on purpose. The per-substep
  cap keeps it bounded but does not guarantee global conservation.
- The single-particle velocity increment does not include a paired
  opposite velocity impulse to every neighbor, so the new post-process
  does not strictly conserve total momentum. It should be used as a
  rendering/visualization-oriented rotational detail method.
- It inherits the base PBF solver's 128 neighbor cap, unilateral
  density constraint and experimental one-way/two-way ray contacts.

Only the independently evaluated mathematics is verified here.
**Native compilation, Godot headless execution, long stress and
cross-platform tests remain required for production readiness.**
