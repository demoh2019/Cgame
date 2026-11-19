# SoftBody3D / SoftBody3D: Coulomb-limited pair friction

Cgame's built-in **Godot Physics 3D** backend now supports optional
tangential velocity friction for its already-implemented two-way XPBD
vertex–face contacts between distinct soft bodies.

## Settings

All in `physics/3d/solver`:

- `soft_body_pair_collision_thickness` must be **positive** to enable the
  existing discrete contact stage (default `0`: disabled).
- `soft_body_pair_collision_friction` is the nonnegative coefficient of
  sliding friction (default `0`: free slip, no extra work).
- `soft_body_pair_collision_compliance`, `soft_body_pair_max_contacts`,
  and `soft_body_pair_max_pairs` retain their previous meanings.

## Algorithm

For one contacting vertex and triangle, the barycentric weights are
`(1, u, v, w)` with the triangle contributions having negative signs.
The relative contact velocity is
`v_rel = v_vertex - (u*v_a + v*v_b + w*v_c)`.
Remove the normal component to compute `v_t`. The effective inverse mass
is `W = im_vertex + u²*im_a + v²*im_b + w²*im_c`.

The unconstrained impulse is `-v_t/W`; the Coulomb bound caps its
magnitude to `mu * lambda_normal / dt`, where `lambda_normal` is the
step-local XPBD normal multiplier from the *preceding* position solver.
The impulse is distributed with the usual mass/barycentric Jacobian.
This preserves total momentum for free particles and cannot increase
kinetic energy in exact arithmetic. Contact normal velocity is unchanged
by the tangential correction. Zero-inverse-mass particles are untouched.

Apply friction **once after all 1–4 normal-contact iterations**, before
refitting the BVHs. Uses double for intermediate reductions, finite-value
checks and transactional velocity commits. No persistent contact buffer.

## Tests and limits

- `tests/servers/test_physics_softbody_pair_friction.cpp`: native tests for
  full/capped sliding, pins, non-adhesion, unchanged normal velocity and
  invalid-input isolation.
- `tests/stress/test_physics_softbody_pair_friction.py`: 3,000 randomized
  numerical reference cases, plus source/configuration wiring checks.
- `.github/workflows/physics-softbody-pair-friction.yml`: PR/develop CI.

This is a **dynamic friction** approximation for discrete contacts, not a
persistent static-friction manifold. It does not resolve high-speed
tunneling, pairs that exceed the existing contact budgets, edge–edge
contact or volumetric FEM. The full engine must be built and tested
in representative scenes before production use. The Jolt backend is
not changed.
