# Progressive tetrahedral continuum damage in Cgame FEM

GodotPhysics3D gains an opt-in **per-element degradation** model for
Neo-Hookean tetrahedral FEM soft bodies. It complements existing surface
stretch/bending plasticity, global volumetric creep, and tetra viscosity.

Inspired by PhysX deformable volume material modeling, but this is an
experimental **scalar continuum damage approximation**, NOT a calibrated
material fracture law. It does not split vertices, cut cracks, or create
new triangles, and does not support arbitrary concave tetra meshes yet.
It operates on Cgame's existing closed, oriented **convex FEM shells**
that can be cooked into a fan of real tetrahedra.

## Project Settings

- \`physics/3d/solver/soft_body_tetra_fem_compliance = 0.00001\`:
  enable volume FEM. Default 0.
- \`physics/3d/solver/soft_body_tetra_damage_rate = 2.0\`:
  progressive damage rate in inverse seconds. **Default 0 (OFF)**.
- \`physics/3d/solver/soft_body_tetra_damage_yield_energy = 0.1\`:
  threshold for elastic energy density divided by unit Young's modulus.
  Default 0.1.
- \`physics/3d/solver/soft_body_tetra_fem_poisson_ratio = 0.3\`:
  existing FEM Poisson ratio.

With energy density \`e = NeoHookeanEnergy / originalTetVolume\`:
\`severity = clamp(e/yield - 1, 0, 32)\` when \`e > yield\`.
The local irreversible damage obeys
\`D_next = min(0.95, 1 - (1-D_prev)*exp(-rate*dt*severity))\`.

At D=0 the local FEM compliance is unchanged. At D=0.5 it doubles.
At D=0.95 it grows to at most 20 times its original value.
Optional tetra reinforcement fibers are also weakened by the same D;
viscous damping and mesh topology remain independent.

The damage update occurs **once** on predicted deformations before the
XPBD iterative constraint solve, not once per iteration. Each cooked
tetra stores one additional double; no new per-step temporary buffers.
Rate 0 skips all extra energy evaluations, preserving the old physics.

## Robustness

- A single tetra can damage independently of neighbors; preserved intact
  neighbors still resist deformation, enabling localized softness.
- Pure rigid translation/rotation has no strain energy, hence no damage.
- Inverted, degenerate, or non-finite elements are rejected by the
  existing FEM strain-energy evaluator.
- Unrepresentable energy or parameter values never mutate the damage.
- Saturation at 0.95 ensures the matrix remains mechanically supported.

## Validation

\`python3 -m unittest discover -s tests/stress -p 'test_physics_fem_tetra_damage.py' -v\`

C++ doctest:
\`tests/servers/test_physics_fem_tetra_damage.cpp\`.

Header compile/run smoke tests in both precision modes:
\`g++ -std=c++17 -O2 -Wall -Wextra -Werror -Itests/stress/physics_cpp_stubs -I. tests/stress/test_physics_fem_tetra_damage_compiler.cpp -o /tmp/fem_damage && /tmp/fem_damage\`

and repeat with \`-DCGAME_USE_DOUBLE\`.

Further development: per-tet plastic deformation gradient, yield surfaces
(von Mises / Drucker-Prager), tearing with dynamic topology updates,
arbitrary tetrahedral meshing and collision/render mesh embedding.
