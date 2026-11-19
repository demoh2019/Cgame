# Cgame Jolt: experimental predictive soft-body vertex–face contacts

## Comparison to Jolt and Bullet

Jolt's rigid bodies have continuous collision detection with LinearCast
motion quality, but Jolt documents native soft bodies as colliding only
with rigid bodies. Cgame's previous additions provide optional soft-soft
vertex–vertex, vertex–face, edge–edge and BVH-accelerated face contacts,
but all of them are discrete and can miss a fast point that crosses a
triangle entirely between physics steps.

This patch adds a deliberately limited, **opt-in linearized sweep**, not an
exact solver for continuous collisions of deforming triangles. Bullet's
soft-body node/face and cluster collision machinery is not copied.

## Settings

Project Settings > Physics > Jolt Physics 3D > Simulation:

- `soft_body_soft_contacts = true` (master setting)
- `soft_body_soft_vertex_face_contacts = true` (required)
- `soft_body_soft_speculative_ccd = true` (new, default **false**)
- `soft_body_soft_ccd_max_sweep = 1.0` metres (0..4)
- `soft_body_soft_ccd_max_correction_speed = 128.0` metres/second (1..256)
- `soft_body_soft_contact_radius = 0.1` metres (existing setting)

All default physics scenes remain in their existing discrete modes. The new
setting is independent of the optional face BVH and edge–edge response.

## Algorithm

During Jolt's **pre-step**, the VF solver is extended only for points
that are currently *outside* the collision radius:

1. Expand body-pair AABB broadphase and, if enabled, face-BVH/triangle AABB
   queries by the maximum configured sweep distance.
2. For each point/face candidate, use the face's initial plane and the
   **relative velocity** between the point and the mean of the three
   triangle velocities. Solve for the time when the point enters the
   two-sided contact shell in the current fixed time step.
3. Reject any sweep with nonfinite inputs, degenerate triangles, relative
   travel above the configured sweep horizon, an outgoing trajectory, or
   time of impact outside the physics step.
4. Evaluate the triangle at the predicted impact time, moving each vertex
   independently with its current velocity. Find the nearest point and
   actual barycentric weights on this interpolated moving triangle.
5. Reject the candidate if the updated triangle is no longer near the
   point (2% tolerance for linearization/numerics).
6. Compute mass-weighted contact impulse from the current barycentric
   velocities, *before* Jolt's simulation advances the particles. Remove
   approaching velocity (up to the configured speed cap) without adding
   an artificial penetration bias for a future contact.
7. Preserve the old discrete impulse/friction algorithm for points
   already inside the contact radius.

The global 1024..65536 work budget still charges each candidate, and
both body traversal directions share it. No per-contact heap allocation.
The same optional face BVH is usable by expanding its point-query margin.

## Important limitations

- **Not mathematically complete deformable CCD.** The TOI plane is based
  on current geometry and *average* triangle velocity; changing face
  orientation/curvature can invalidate this approximation.
- Detects crossings of the plane contact shell, not arbitrary tangential
  movement into a triangle from outside an edge. It can miss collisions
  from very fast movement beyond the configured horizon.
- This is a **predictive velocity impulse**; it does not rewind the soft
  body to the contact time or perform Jolt's rigid-body LinearCast.
- The BVH and body AABB are expanded by a fixed sweep margin; highly
  divergent per-vertex velocities are not guaranteed to be enclosed.
- Bounded impulse correction can be insufficient when relative velocity
  exceeds the configured cap, allowing tunneling.
- Future contact prediction can cause premature deceleration in strongly
  shearing or rotating triangles. This is an opt-in experimental mode.
- No full soft-soft continuous edge–edge sweep, exact time of impact for
  deformable triangles, soft self-collision, persistent manifolds or FEM.
- More face queries per step are expected. Measure FPS, peak RAM and
  skipped work before enabling in production.

## Regressions

Independent reference math/source checks:

    python3 -m unittest tests/stress/test_jolt_soft_soft_speculative_ccd.py -v

Native Jolt scene after Cgame compilation:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress/jolt_soft_soft_sweep \
      --script res://swept_triangle_regression.gd

Native fixture: fast tetrahedron is propelled ~35 m/s toward a deformable
8x8 grid. An identical control pair has collision masks disabled.
Tests check reduced tunneling, finite positions, and corner pins.

Compilation and native simulation are NOT proven by source/math tests.
