# FEM tetrahedral inversion recovery — GodotPhysics3D

Experimental **opt-in** mass-weighted correction of collapsed or
inside-out tetrahedral elements. Uses a unilateral local volume
constraint before Neo-Hookean FEM: unlike the logarithmic elastic
model, this correction can be evaluated even at negative determinant.

Inspired by XPBD/PBD tetrahedron volume constraints and the
inversion-handling strategies in InteractiveComputerGraphics'
PositionBasedDynamics reference implementation.

## Settings

- \`physics/3d/solver/soft_body_tetra_fem_compliance\` must be > 0
  (for example 0.00001) so the convex-shell FEM tetrahedralization
  is created.
- \`physics/3d/solver/soft_body_tetra_inversion_recovery = true\`:
  opt-in correction; default **false**.
- \`physics/3d/solver/soft_body_tetra_inversion_min_j = 0.05\`:
  minimum determinant ratio J=det(F), accepted range 0.001..0.5.

For each tetra with J below the configured threshold:

\`grad(J)_i = grad(det(Ds))_i / det(Dm)\`
\`lambda = (min_J - J) / Σ_i inverse_mass_i * |grad(J)_i|²\`
\`x_i = x_i + inverse_mass_i * grad(J)_i * lambda\`

The correction has up to 8 local iterations with 12 backtracking
attempts per iteration. A candidate must increase J and must not
inflate the element above J=1, which limits overshoot. Deformation
gradients are recomputed each iteration, and all four vertices are
committed together only after validating the candidate geometry.

The recovery runs **before** the existing FEM Neo-Hookean constraint
during iterative physics solving, rather than replacing it.
An already-valid element is untouched. Pinned vertices stay fixed;
a fully pinned element cannot recover.

No per-tet allocation, no scene-topology modification, and no overhead
when recovery is disabled beyond a single branch inside the FEM loop.

## Limits

- Existing FEM mesh cooking still supports only validated, closed
  **convex** surfaces that form a fan of tetrahedra.
- This is a geometric projection, not an implicit energy-minimization
  solver or a physically calibrated contact/fracture model.
- Recovery may be incomplete for extremely distorted elements, zero
  effective mass, or impossible pin configurations.
- The solver cannot repair a tetra whose rest matrix is invalid.
- It does not add new fracture surfaces, re-tetrahedralize, or replace
  collision detection.

## Testing

C++ doctest:
\`tests/servers/test_physics_fem_tetra_inversion_recovery.cpp\`

Randomized reference + source contracts:

\`python3 -m unittest discover -s tests/stress -p test_physics_fem_tetra_inversion_recovery.py -v\`

Compiler smoke using actual FEM headers in both float and double precision:

\`g++ -std=c++17 -O2 -Wall -Wextra -Werror -Itests/stress/physics_cpp_stubs -I. tests/stress/test_physics_fem_tetra_inversion_recovery_compiler.cpp -o /tmp/inversion && /tmp/inversion\`

Repeat with \`-DCGAME_USE_DOUBLE\`.
