# Anisotropic XPBD stretch for GodotPhysics3D SoftBody3D

## Why

The built-in GodotPhysics3D solver previously used the same compliant XPBD
distance constraint for every structural link. Woven cloth, layered materials,
fibrous ropes, and anisotropic soft surfaces need different stretch response
along a preferred material axis and across it. Jolt supports per-edge
compliance and Cgame's Jolt integration already experiments with per-fiber
directional compliance. PhysX has more general GPU FEM deformables; this patch
deliberately implements a smaller, CPU-only material model rather than
pretending to match a full finite-element simulator.

## Configuration

Set these Project Settings before creating a PhysicsSpace3D:

- physics/3d/solver/soft_body_xpbd_compliance: a finite positive value
  enables XPBD stretch. Zero retains legacy link solver.
- physics/3d/solver/soft_body_xpbd_fiber_axis: Disabled (default), X, Y or Z,
  selecting the fiber direction in original mesh-local/source coordinates.
- physics/3d/solver/soft_body_xpbd_fiber_compliance_ratio: 0.1..10, default
  1.0. Ratio below 1 means stiffer along fibers; above 1 means softer
  along fibers. Ratio 1 reproduces isotropic XPBD.

These settings are cached when the space is initialized. Recreate the
physics space to apply changes to existing soft bodies.

For each edge with source direction d and selected unit basis e:

    t = dot(d, e)^2 / dot(d, d)
    alpha_directional = alpha_isotropic * (1 + (ratio - 1) * t)

The same distance-constraint solver, pinning, compliance/time-step scaling,
and one-step lambda storage are reused. This interpolation is intentionally
independent of current deformation, so rotating the cloth during simulation
does not rotate/change the material's rest frame.

## Performance and stability

- All defaults preserve the isotropic branch, without an extra traversal,
  per-link storage, or more narrowphase work.
- When enabled, an O(number of links) pass caches each link's effective
  compliance once per step, avoiding angle math inside every solver
  iteration. The cache capacity is reused between steps.
- An extra real_t per link is held while enabled; disabled mode frees it.
- Invalid source geometry and ratios fall back to isotropic compliance.
  Finite extreme-scale rest coordinates are normalized before squaring.
  Effective alpha is saturated to the representable real_t maximum.
- The model introduces no new contacts, springs, time integration, FEM mesh
  or inter-soft-body collisions. It changes only compliant stretch.

## Regression validation

Pure Python numerical/source contracts:

    python3 -m unittest discover -s tests/stress -p test_physics_xpbd_fiber.py -v

After building a native Cgame editor with tests=yes, run the six
[PhysicsXPBDFiber] doctests. Native compilation, end-to-end cloth scenes,
headless simulations, and performance benchmarks on production mesh sizes
must still be completed before merging into develop.

Compare isotropic and anisotropic cloth using the same mesh, timestep,
solver iterations, material compliance, and hardware. Record p50/p95
physics-step CPU time and peak RSS for 1k, 10k, and 100k link scenes; check
pinned vertices, mesh translation/scaling, frame-rate sensitivity and
orientation-dependent stretch. The optional cache adds expected memory
O(links), not an optimization claim. Use a debug visualization to verify that
the local material axis matches the desired weave direction.

## References

- https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md
- https://nvidia-omniverse.github.io/PhysX/physx/5.7.0/docs/DeformableBodyOverview.html
