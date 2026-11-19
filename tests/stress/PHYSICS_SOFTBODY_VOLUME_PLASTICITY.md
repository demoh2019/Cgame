# Viscoplastic global volume response for GodotPhysics3D SoftBody3D

Cgame now supports optional **permanent crushing and swelling** of closed
soft-body shells, extending the existing link stretch plasticity and
hinge bending plasticity.

This is a phenomenological XPBD volume model, NOT volumetric tetrahedral
finite-element deformation. The mesh topology remains unchanged.

## Configuration (Project Settings)

1. Set \`physics/3d/solver/soft_body_xpbd_volume_compliance\` to a
   positive value (e.g. \`0.00001\`). The mesh must be closed, manifold,
   and consistently wound. Open cloth and invalid shells do nothing.
2. Set \`physics/3d/solver/soft_body_volume_plastic_creep_rate\` above
   zero (e.g. \`2.0\`, units 1/s). Default is **0** — no extra work.
3. Set \`physics/3d/solver/soft_body_volume_plastic_yield_strain\` (default
   **0.15**) to the allowed relative recoverable volume strain.

If the predicted signed current volume exceeds the elastic window
around the previous mechanical rest volume, update its rest target:

\`target = current / (1 + yield)\` for expansion beyond yield;
\`target = current / (1 - yield)\` for compression beyond yield.

Then \`rest_new = rest_old + (target - rest_old) * (1 - exp(-rate * dt))\`.

The target is clamped to **2%-2000%** of its original volume, and
inverted, collapsed or nonfinite geometry is rejected. Signed winding
is preserved. The update runs **once per simulation step, before XPBD
volume projection**; it does not accumulate creep for every solver
iteration. No per-face or per-node allocations are introduced.

## Sealed gas behavior

The gas pressure law stays anchored to the **original enclosed volume**
even after mechanical rest volume changes. This preserves a fixed gas
reference/mass: permanent crushing still increases pressure rather
than silently modifying the gas mass or resetting gas pressure.
The original rest volume costs one additional 8-byte double per body.

## Validation

Python numerical and wiring contracts:

\`python3 -m unittest discover -s tests/stress -p test_physics_softbody_volume_plasticity.py -v\`

C++ doctest:
\`tests/servers/test_physics_softbody_volume_plasticity.cpp\`.

Future work: tetrahedral FEM plastic constitutive models (von Mises /
Drucker-Prager), local deformation and topology-changing fracture.
