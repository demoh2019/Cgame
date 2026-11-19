# Cgame native CPU PBF fluid — first dynamic particle-fluid milestone

## Why this is not the existing buoyancy solver

Cgame already has horizontal fluid-plane buoyancy/drag for rigid shapes
and experimental soft-body and FEM solvers. None of those steps advances
a freely moving collection of **liquid particles** with local density
constraints. In contrast, a PBF fluid can pour, slosh, settle and be
stirred as individual particles.

This patch adds the experimental built-in scene class
`PBFParticleFluid3D : Node3D`. It follows the Position Based Fluids
model by Macklin and Müller (2013), with feature scope informed by
SPlisHSPlasH's PBF/SPH support:

- https://blog.mmacklin.com/project/pbf/
- https://splishsplash.physics-simulation.org/features/

The implementation is **original code**, not a copy of another engine.

## Algorithm

For each fixed-time substep:

1. Integrate velocity under local gravity and predict particle positions.
2. Sort particles into an integer grid of cell width `h`
   (the smoothing radius). Each particle queries up to 27 adjacent grid
   cells using binary search. A deterministic 128-neighbor cap guarantees
   bounded work even in a singular dense pile.
3. Measure SPH density with the normalized 3D poly6 kernel

   `W(r,h) = 315/(64πh³) · (1 - (r/h)²)³`, when `|r| < h`.

4. Solve a unilateral density constraint

   `C_i = max(ρ_i/ρ_rest - 1, 0)`,
   `λ_i = -C_i / (Σ_j |∇C_ij|² + |∇C_ii|² + 10⁻⁶)`.

   The gradient is the **analytic derivative of the SAME poly6
   density kernel**; it is not an unrelated force approximation.

5. Apply the PBF displacement with artificial anti-clumping pressure

   `Δp_i = (m/ρ_rest) Σ_j (λ_i + λ_j + s_corr) ∇W(p_i - p_j)`,
   `s_corr = -k[W(r)/W(0.3h)]⁴`.

6. Repeat the density projection 1–12 times (default four).
7. Infer velocities from corrected positions. Apply optional one-way
   sweeps against rigid collision shapes and reflect outward velocity
   components at the tank boundary.
8. Apply an optional XSPH velocity filter using the neighborhood grid.

The solver splits user timesteps into up to eight substeps of at most
1/60 s and uses finite checks, bounded positional corrections and
bounded stirring velocities. Storage is persistent and reused between
physics ticks. **No persistent allocations** are needed after
`create_block()`/ `set_particle_positions()`, except engine internal
sort mechanics (to be profiled separately).

## Built-in scene API

The class is registered in `scene/register_scene_types.cpp` and
compiled automatically by `scene/3d/physics/SCsub`'s wildcard source
list, with complete class documentation in
`doc/classes/PBFParticleFluid3D.xml`.

```gdscript
var fluid := PBFParticleFluid3D.new()
fluid.smoothing_radius = 0.37
fluid.particle_mass = 6.0
fluid.rest_density = 1000.0
fluid.solver_iterations = 5
fluid.box_min = Vector3(-2, 0, -2)
fluid.box_max = Vector3(2, 4, 2)
add_child(fluid)

assert(fluid.create_block(Vector3(-0.8, 1.5, -0.8),
        Vector3i(7, 5, 7), 0.21))
fluid.simulation_enabled = true
# On key press, stir the fluid locally.
fluid.add_velocity_pulse(Vector3(0, 1, 0), 1.5, Vector3(3, 4, 0))
```

This node only simulates particles; for a visible fluid, copy
`fluid.get_particle_positions()` into a `MultiMeshInstance3D` or
a custom liquid surface renderer. The Physics Lab uses one instanced
mesh for its 245-particle fluid station at approximately
`(-28, 0, -11)`. Camera TAB cycles to the tank; keyboard controls:

- `U`: refill/restart the tank
- `I`: pause/resume the PBF solver
- `O`: add a velocity impulse that visibly stirs the water

The rest of the engine runs unchanged. No particle buffers are
allocated and no physics tick runs until the class is explicitly
created, seeded and enabled.

## Correctness and stability tests

**Independent numerical/source contracts:**

```bash
python3 -m unittest discover -s tests/stress -p 'test_physics_pbf_3d.py' -v
```

Tests include radial normalization of W, 1500 random kernel
gradient derivatives against finite differences, 120 random particle
clouds comparing grid neighbors against brute force, compressed
27-particle lattice density projection, center-of-mass symmetry, and
registration/integration source checks.

**Native doctests** in `tests/servers/test_physics_pbf_3d.cpp`:

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 \
  --headless --test --test-case="*[PhysicsPBF3D]*" \
  --success=true --no-colors
```

**Native engine SceneTree regression:**

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_pbf_particle_fluid_3d_regression.gd
```

**Physics Lab headless smoke:**

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path demo/physics_lab --script res://smoke_test.gd
```

The smoke test checks for a real registered C++ PBF node and 245
particles, not just visual placeholder geometry.

**CPU/RSS benchmarks:** two standard stress runner cases create
identical particle clouds from 80 to 2048 particles and compare an
inactive instance with an actively integrating PBF scene node.
They report frame p95, physics time, peak memory (via the stress
harness), and neighbor count.

```bash
python3 tests/stress/run.py --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_pbf_3d_disabled,physics_pbf_3d_enabled \
  --scales 1,2,4,8 --frames 120 --repeats 3 \
  --output physics-pbf-stress.json
```

Run `--help` for your branch's exact stress-runner flags. A native
tests-enabled editor binary must be built first. These checks are
also registered in
`.github/workflows/physics-pbf-fluid.yml` and the full native
`whole-engine-stress.yml` pipeline.

## Intentional limitations

This is **stage one of a native dynamic liquid solver**:

- The PBF constraint is unilateral. At the free surface this avoids
  forcing all low-density particles to fill artificial volume, but is
  not a perfect incompressible volume conservation solver.
- Rigid-body collision sweeps are **one-way**, disabled by default,
  and currently use a ray for the particle center with a contact
  offset. The code does not apply reaction impulses to rigid bodies,
  so there is no two-way momentum conservation. Deep starting
  overlaps or rapidly rotating obstacles may escape the ray.
- Local AABB box walls are rigid and axis-aligned. They do not
  simulate fluid-solid boundary particles or pressure on a curved
  immersed obstacle.
- The 128-neighbor limit is a safety cap; when saturated, pair
  neighborhoods can become asymmetric and total momentum is not
  guaranteed to be exactly conserved. It is a conservative
  performance tradeoff, not a complete DFSPH solver.
- No dynamic surface mesh, fluid self-shadowing, multiphase,
  temperature, surface tension curvature, wetting, foam or GPU
  compute pipeline. XSPH damping is an approximation to viscosity.
- Does not automatically interact with GodotPhysics3D's existing
  horizontal water plane; both systems are optional and independent.

Future integration steps: two-way rigid boundary particles with
momentum transfer, DFSPH divergence correction, dynamically reconstructed
liquid surface and GPU compute acceleration.

**Production-readiness has not been established.** Native C++ build,
headless runtime, finite-check stress, memory/CPU profiling and
platform-specific editor serialization must pass before merging.
