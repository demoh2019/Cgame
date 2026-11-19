# Experimental progressive tetrahedral FEM damage — Cgame

This feature adds a bounded, irreversible scalar *material damage*
variable per tetrahedron to the **Godot Physics 3D SoftBody3D** backend.
It is inspired by deformation-dependent material properties in FEM
solvers. It does **not** break geometry or change topology.

PhysX 5.7 describes volumetric finite-element deformables with simulation
and collision meshes; this Cgame feature stays CPU/XPBD and reuses its
existing closed, convex tetrahedral fan, not PhysX code.

## Configuration

Under `physics/3d/solver`:

- `soft_body_tetra_fem_compliance > 0`: required to cook/solve tetra FEM.
- `soft_body_tetra_damage_rate`: 0 by default, disabled; positive values
  enable the new progressive damage history (1/s).
- `soft_body_tetra_damage_yield_strain`: default 0.15; normalized
  Green–Lagrange strain threshold for the *onset* of softening.
- `soft_body_tetra_damage_max`: default 0.8, clipped to [0, 0.95].
  Prevents infinite/undefined XPBD compliance. 0 disables damage.

Positive damage makes Neo-Hookean *and fiber reinforcement* constraints
softer via `effective_alpha = alpha/(1-damage)`. The original rest
tetrahedra, mass, collision constraints and mesh topology stay unchanged.
The scalar damage is irreversible during a mesh's lifetime, but is reset
when the soft body is reconstructed or the feature is switched off.

## Formula and performance

For the current deformation gradient
`F = Ds * inverse(Dm)` and Green–Lagrange tensor
`E=(F^T F-I)/2`, the triggering strain is the dimensionless
`sqrt((2/3)*(E:E))`. This detects shear, compression and stretching.
It is invariant under translations and rigid world rotations, and
rejects inverted/singular elements.

For yield `y`, rate `r`, time step `dt` and maximum damage `Dmax`:

```
excess = max(0, strain - y)
severity = excess/(1 + excess)
fraction = 1 - exp(-r * dt * severity)
D_next = D + (Dmax-D) * fraction
```

This expression cannot heal damage and is independent of substep count
for constant strain. The one-pass update occurs after position
prediction but **before** FEM/XPBD corrections; measuring only the
post-projection state would hide damage from stiff bodies.

RAM cost: one `real_t` scalar per valid FEM tetrahedron, **only when
enabled**, plus stack-local 3x3 tensors. Default mode adds no per-element
allocation or tensor traversal. Normal and fiber XPBD lambdas retain
their existing per-step semantics.

## Tests

- `tests/servers/test_physics_fem_tetra_damage.cpp`: 8 C++ Doctest
  cases including exact rotation invariance, shear, compression,
  tension, scale invariance, rate splitting and input guards.
- `tests/stress/test_physics_fem_tetra_damage.py`: 6,000 seeded
  objective-strain/softening reference tests, substep invariance, source
  wiring.
- `.github/workflows/physics-fem-tetra-damage.yml`: dedicated CI.

## Known limitations

No physical fracture, crack propagation, tetra separation or permanent
rest-shape plastic flow. These require mesh-topology changes or
multiplicative plasticity and new collision faces. Damage from a heavily
inverted tetrahedron is skipped, not used to repair the element. Only
the existing convex, closed-shell FEM cooker is supported. The trigger
is a phenomenological Green-strain norm rather than a calibrated
fracture-energy/strength criterion.

The full C++ engine build, live scene tests and CPU/RSS benchmarks
must be completed before treating this experimental feature as
production-ready.
