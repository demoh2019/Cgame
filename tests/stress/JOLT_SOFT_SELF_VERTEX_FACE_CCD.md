# Cgame/Jolt: bounded continuous self vertex–face collision prediction

## Comparison with other engines

Upstream **Jolt Physics** supports deformable bodies with XPBD internal
constraints, but currently documents that soft bodies only collide with
rigid bodies. **Bullet**'s `btSoftBody::fCollision` exposes `VF_SS`
(vertex–face soft/soft), `CL_SS` (cluster soft/soft) and `CL_SELF`
(cluster-based self collisions). None of those libraries supplies native
Cgame self vertex/face CCD; this implementation is independently authored.

Earlier Cgame opt-in self vertex/face contacts use a **discrete** closest
point/triangle test. A vertex moving fast may start outside the contact
shell, pass through a disconnected triangle, and leave it between frames.
The new mode uses **conservative advancement** on the fully deforming
triangle, with an explicitly bounded work quota.

## Enable

Under `physics/jolt_physics_3d/simulation/`:

- `soft_body_self_contacts=true` (required existing self-collision master)
- `soft_body_self_speculative_vertex_face_ccd=true` (**new; default false**)
- `soft_body_self_contact_max_checks=16384` (existing per-space quota)
- `soft_body_soft_contact_radius=0.1` m (existing shell thickness)
- `soft_body_soft_ccd_max_sweep=1.0` m (existing finite-clamped 0..4m)
- `soft_body_soft_ccd_max_correction_speed=128.0` m/s (existing cap)

The self VF CCD option is **independent** of inter-body
`soft_body_soft_speculative_ccd` and self-edge CCD. The latter may
be used together for additional coverage.

## Physics algorithm

For a particle at `p` and its velocity `v_p`, and a face
`(a,b,c)` with independently moving velocities `(v_a,v_b,v_c)`:

1. Reject all topologically adjacent faces using the existing
   one-ring mesh filter; neighbors and own faces cannot cause impulses.
2. Use the **current** deforming-face BVH (when its face-count/budget
   allows it), otherwise the existing brute-force scan. Expand both
   BVH queries and exact face AABB tests by
   `contact_radius + max_sweep` only in speculative mode.
3. If the point is **already within the contact radius**, use the
   unchanged discrete impulse and optional XPBD-style Jacobi positional
   projection. Never mix this case with future-contact prediction.
4. For a separated candidate, compute the maximum of **three**
   endpoint-relative speeds `|v_p-v_a|`, `|v_p-v_b|`, `|v_p-v_c|`.
   In linearized motion, the distance from the point to the moving
   triangle cannot shrink faster than this bound, even as the closest
   feature changes between triangle interior, edges, or corners.
   Reject pairs with `max_speed * dt > max_sweep`.
5. Starting at `t=0`, compute the **seven-region closest point to
   the triangle after moving all four particles to time t**. Advance
   by `(current_distance - radius)/max_speed`. Stop at the shell, the
   end of the physics step, or **16 iterations**. Every evaluation
   is charged to the existing *self vertex-face* budget, on top of
   the initial candidate test. No per-contact memory allocation.
6. At a predicted contact, use the impact-time barycentric weights and
   normal. Reject tangential/outgoing relative motion. Apply an
   equal-and-opposite, inverse-mass-weighted velocity impulse to all
   four vertices with the existing CCD correction-speed limit. Pinned
   vertices remain unchanged and existing Coulomb friction is retained.
7. A future contact gets **zero penetration bias** and **no positional
   projection**. Only an actual overlapping contact may be positionally
   corrected. This preserves compatibility with the existing one-pass
   Jacobi self-contact solver and Jolt's XPBD internals.

### Why the expanded BVH remains conservative

Every point on a triangle at time t is a barycentric combination of
its current corners with the same barycentric weights, moving under
a convex combination of their velocities. Its motion relative to the
vertex is bounded by the maximum point-to-corner relative velocity.
Therefore any pair accepted by the sweep horizon could not move into
contact within one step if their original point/AABB separation in any
axis exceeded `contact_radius + max_sweep`.

This is an inexpensive **conservative broadphase for accepted linear
sweeps**; it may include many false positives but will not skip eligible
pairs because of the static AABB. All visits/tests still spend budget.

## Limitations

- **Not exact continuous deformable physics**: actual soft-body
  trajectories under native Jolt XPBD constraints, collisions and
  accelerations can deviate from the constant-velocity prediction.
- The maximum of 16 iterations may miss difficult near-grazing or
  almost-degenerate cases. The per-space budget may be exhausted early.
- There is no time-of-impact rewind, contact manifold warm-starting,
  exact cubic triangle CCD, multi-iteration XPBD self-contact solve,
  mesh cutting, plasticity, damage propagation or FEM.
- Face BVH is rebuilt each step; caching/refitting it is a separate
  future optimization. The existing *edge* BVH cache is unaffected.
- High `max_sweep` increases the BVH search footprint and CPU costs.
- Mode is off by default and should remain experimental until native
  C++ compilation, running the headless scene and performance profiling.

## Tests

Independent Python geometry, moving/sheer/rotating-face and source tests:

    python3 -m unittest tests/stress/test_jolt_soft_self_vertex_face_sweep.py -v

Native physics regression requiring a compiled Cgame editor:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress/jolt_soft_self_vf_sweep \
      --script res://swept_self_triangle_regression.gd

The native scene uses a **single soft body consisting of two disconnected
triangles**, a fast-moving source face and a pinned target face. Control
has identical topology/masses/speeds but its target is offset 3m in X.
Both bodies have layers/masks zero. Gravity, velocity-penetration recovery,
self edge collision and Jacobi projection are disabled to isolate the
new CCD impulse. The script asserts finite coordinates, pins and reduced
travel against the unopposed control. A passing native scene demonstrates
this case, not unconditional CCD or a performance gain.
