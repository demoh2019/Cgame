# GodotPhysics3D: optional swept structural edge/edge CCD for SoftBody3D

This adds an **opt-in** continuous edge/edge *intersection* test alongside
the already-present discrete XPBD structural edge solver and swept vertex/face
CCD. It targets fast cloth crossings missed by vertex/face tests when neither
edge endpoint enters the opposing triangle.

## Independent references

- PositionBasedDynamics has independent edge/edge distance constraints and
  XPBD approaches for cloth, rods, deformable solids and fluids. This patch
  implements its own CCD narrowphase and does not copy that library's code.
- Bullet soft bodies offer vertex/face and cluster-based soft collisions. The
  edge-pair treatment here is specifically for GodotPhysics3D structural edges.
- Jolt currently documents soft-vs-soft collisions as outside its native
  soft-body collision pipeline; Cgame's experimental Jolt soft-soft contacts
  are a separate backend and are **not** modified by this patch.

## Configuration (both flags default to false)

```ini
physics/3d/solver/soft_body_self_collision_thickness=0.12
physics/3d/solver/soft_body_self_collision_compliance=0.000001
physics/3d/solver/soft_body_self_collision_edge_edge=true
physics/3d/solver/soft_body_self_collision_ccd=true
```

The existing CCD flag now controls swept candidate envelopes for BOTH
vertex/face and structural edge/edge self contacts. Both flags and positive
thickness are required for edge CCD; setting either flag false keeps the
prior discrete or disabled behavior. Values are cached when a physics space
is created, so recreate the space after adjusting settings.

## Algorithm

1. The same unique, nonadjacent structural edges and BVH are reused.
   With CCD on, **both previous and current endpoints** enter the per-edge
   BVH envelope and per-edge query, conservatively covering linear motion.
2. Discrete contacts are attempted first; they remain in the compact buffer.
3. For candidate pairs missed by discrete contacts, calculate the cubic
   coplanarity determinant `(A(t)-C(t)) · ((B(t)-A(t)) × (D(t)-C(t)))`.
   Its derivative is quadratic; partition [0,1] at extrema to find every
   sign-changing root with bounded bisection. A true hit requires both
   closest-point parameters to lie strictly inside [0,1].
4. Freeze the first valid impact's two barycentric edge weights and orient
   the separating normal toward their **previous** signed side.
5. Solve a unilateral mass-weighted XPBD contact against the final positions,
   preserving pins and rejecting any non-finite candidate updates.

There is no new per-step all-pairs search, global heap allocation in the
narrowphase, or persistent lambda storage. The existing 65,536 contact
budget covers discrete + continuous edge contact buffers together, and
the existing per-edge cap applies to both.

## Limitations

- Only *transversal* coplanarity crossings with interior segment witnesses
  are detected. Grazing/tangent, initially coplanar, parallel, edge-endpoint
  and degenerate intersections are not full CCD; vertex/face contacts may
  handle some of them.
- Endpoint trajectories are approximated as linear over a physics step.
  True continuous elastic deformation and rigid angular trajectories with
  intermediate acceleration need other techniques.
- Corrections are XPBD positions at the end of a step, not true event-driven
  time splitting, impact impulses or complete frictional contact manifolds.
- Multiple contacts may be order dependent. The contact cap can truncate
  dense fold interactions. This remains an experimental opt-in mode.
- Jolt and other backends are not changed. No performance improvement or
  production stability is claimed without native, end-to-end validation.

## Verification

```bash
python3 -m unittest discover -s tests/stress -p test_physics_xpbd_edge_ccd.py -v

# tests=yes native Cgame build:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="*[PhysicsEdgeCCD]*" --success=true --no-colors

# Real scene-based comparison with two disconnected, crossing cloth strips:
python3 tests/stress/run.py \
  --godot ./bin/godot.linuxbsd.editor.dev.x86_64 \
  --case physics_soft_body_edge_ccd_3d --preset smoke \
  --output out/swept-edge-ccd.json
```

Measure isolated frame/step p50/p95/p99, process RSS and missed contacts
at increasing cloth triangle counts, at 60/120/240 Hz, with edge CCD
disabled and enabled on identical geometry. The baseline is important:
more swept candidates and polynomial tests may increase CPU cost.
