# GodotPhysics3D soft-body vertex/triangle self-collision

This patch adds **experimental discrete self-collision of a soft mesh with
itself**. It is intended to stop nonadjacent regions of deforming cloth
from occupying the same space, complementing Cgame's existing XPBD stretch,
dihedral bending, triangle area, volume, and tether constraints.

The implementation uses Cgame's existing **DynamicBVH triangle tree** for
broadphase, following the vertex-triangle approach to cloth self-collision
in the Position-Based Dynamics literature. This is intentionally a
limited discrete contact solver rather than FEM, tearing, inter-body
soft-soft collision, or continuous self-collision CCD.

## Enable explicitly

Select `GodotPhysics3D` and set in Project Settings -> Physics -> 3D -> Solver:

```ini
[physics]
3d/physics_engine="GodotPhysics3D"
3d/solver/soft_body_self_collision_thickness=0.02
3d/solver/soft_body_self_collision_compliance=0.0
```

- `soft_body_self_collision_thickness=0.0` (default) **disables** all
  self-collision broadphase, topology building and contact projection.
  Positive thickness is in world units (meters). Choose a value smaller
  than the local cloth mesh spacing.
- `soft_body_self_collision_compliance=0.0` (default) uses the rigid
  position-projection limit when self collision is enabled. Higher values
  yield softer collision response. Compliance is scaled by `1/dt²`.
- Values are sanitized as finite, nonnegative values once per
  GodotPhysics3D physics space. Recreate the world to apply changes.

## Pipeline

1. The optional one-time mesh adjacency set stores each *structural*
   triangle edge as a compact 64-bit key. It rejects collisions of a
   vertex against its own triangles and against the one-ring triangles
   incident to an immediately connected vertex. This prevents adjacent
   cloth triangles from repelling during normal bending.
2. After predicting motion and solving stretch, bending, area, volume,
   and tether constraints, refit the soft mesh's **existing face BVH**
   for its current positions.
3. For each vertex, query nearby triangles within a cube of thickness.
   Reject degenerate faces, incident/adjacent faces and faces farther
   than the thickness according to the *true* closest point on the
   triangle (including vertices/edges, not just its infinite plane).
4. Retain the **four closest nonadjacent triangles per vertex**, sorted
   by (squared distance, face ID). This avoids dependence on BVH
   traversal order when the tree is incrementally rebalanced.
   Gather candidates for the whole mesh **before** moving any vertex;
   that way all candidate queries observe a consistent snapshot.
5. Apply a one-pass, **two-sided, inverse-mass-weighted position
   correction**. The point receives a displacement along the separating
   direction and each triangle vertex receives the opposing displacement
   weighted by its closest-point barycentric coordinate and inverse
   mass. Pinned particles (inverse mass 0) remain fixed. At exactly
   zero separation, use the point's previous side of the triangle or
   fall back to face winding to choose a normal.
6. Refit the face BVH again if contacts were collected, so ray queries
   and next-frame prediction do not use stale bounds. Reconstruct
   particle velocities **after** contact correction, preventing a
   spurious pop on the following step.

## Bounded cost and memory

Avoiding a naive O(vertices * faces) full scan is critical. We reuse the
existing BVH (no new spatial index) and apply three strict budgets:

- at most **4 retained candidate faces per vertex**;
- at most **65,536 total stored contacts per step**;
- at most **128 face leaves inspected per vertex** and **1,048,576**
  total face leaves inspected per soft-body step.

A transient `LocalVector` stores pairs of 32-bit (vertex, face) IDs
and is reused across frames. The adjacency set is built only after
self collision is enabled and is cleared on mesh destruction. There is
no extra hot-path ProjectSettings read. CPU/RAM can increase in enabled
mode, especially when many layers are packed closely; strict limits
prevent unbounded candidate storage or narrowphase leaf tests, but do
not guarantee a constant-time BVH traversal.

The finite candidate budget is a **quality/performance compromise**:
on scenes with extreme self-overlap it may skip some contacts. Do not
assume every overlapping pair is resolved in a single step. Other
structural constraints are left unchanged.

## Physical limitations

- **Discrete only**: a vertex may tunnel completely through a triangle
  between steps. Fast/violent folds require a smaller timestep or
  future swept vertex-triangle CCD.
- Resolves **vertex vs triangle** only. Thin crossed edges without a
  nearby vertex, self-intersecting faces, and continuous edge-edge
  contact are not supported.
- One Gauss-Seidel position-projection pass per physics step, not a
  full XPBD persistent-contact manifold or frictional self collision.
- The one-ring exclusion is topological; close but nonadjacent
  triangles can still collide even if they belong to the same shell.
- There is no inter-soft-body collision; only self contacts *within
  one soft body* are handled.
- Enabled work runs after volume/stretch correction, so the solver
  trades exact other constraints against separation; more substeps
  improve quality but cost CPU. This feature is experimental.

## Test commands

```sh
# Source contracts (does not replace a native build)
python3 -m unittest discover -s tests/stress -p 'test_physics_softbody_self_collision.py' -v

# Native helper regression (requires editor built with tests=yes)
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision triangle closest point covers all Voronoi regions"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision separates vertex from pinned triangle to thickness"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision mass weighting respects pinned vertices and compliant contacts"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision rejects invalid and degenerate triangles without mutation"
```

Before merging, test a small folded cloth, a hanging pinned sheet, an
open sheet and a non-manifold triangle mesh under identical scene
conditions with self collision OFF and ON. Compare collision
penetrations, frame time p50/p95/p99, peak RSS, allocator churn and
NaN counts. The feature is **not a speedup claim**. Full native
compilation, scene regressions and profiling remain prerequisites.

Further reading:
- Original Position-Based Dynamics cloth self-collision paper:
  https://matthias-research.github.io/pages/publications/posBasedDyn.pdf
- XPBD method and constraints:
  https://developer.blender.org/docs/features/nodes/xpbd_solver/
- Jolt's documented soft-body limitations:
  https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md
