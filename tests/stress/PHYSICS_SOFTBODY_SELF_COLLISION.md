# GodotPhysics3D soft-body vertex–triangle and edge–edge self-collision

This patch adds **experimental discrete self-collision of a soft mesh with
itself**. It is intended to stop nonadjacent regions of deforming cloth
from occupying the same space, complementing Cgame's existing XPBD stretch,
dihedral bending, triangle area, volume, and tether constraints.

The implementation uses Cgame's existing **DynamicBVH triangle tree** for
broadphase, following the vertex–triangle and segment–segment approach to cloth
self-collision in the Position-Based Dynamics literature. This is intentionally a
limited discrete contact solver rather than FEM, tearing, inter-body
soft-soft collision, or continuous self-collision CCD.

## Enable explicitly

Select `GodotPhysics3D` and set in Project Settings -> Physics -> 3D -> Solver:

```ini
[physics]
3d/physics_engine="GodotPhysics3D"
3d/solver/soft_body_self_collision_thickness=0.02
3d/solver/soft_body_self_collision_compliance=0.0
3d/solver/soft_body_self_collision_edge_contacts=true
```

- `soft_body_self_collision_thickness=0.0` (default) **disables** all
  self-collision broadphase, topology building and contact projection.
  Positive thickness is in world units (meters). Choose a value smaller
  than the local cloth mesh spacing.
- `soft_body_self_collision_compliance=0.0` (default) uses the rigid
  position-projection limit when self collision is enabled. Higher values
  yield softer collision response. Compliance is scaled by `1/dt²`.
- `soft_body_self_collision_edge_contacts=false` (default) enables the
  **additional** crossed-edge/near-edge narrowphase only when set to true
  *and* thickness is positive. Existing vertex–triangle simulations keep
  their previous cost and behavior unless explicitly enabled. An edge
  crossing without any close endpoints is therefore detectable.
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
   by (squared distance, face ID) among visited faces. With a saturated
   search budget, a BVH rebalance can change which faces were visited.
   Gather candidates for the whole mesh **before** moving any vertex;
   that way all candidate queries observe a consistent snapshot.
5. Apply a one-pass, **two-sided, inverse-mass-weighted position
   correction**. The point receives a displacement along the separating
   direction and each triangle vertex receives the opposing displacement
   weighted by its closest-point barycentric coordinate and inverse
   mass. Pinned particles (inverse mass 0) remain fixed. At exactly
   zero separation, use the point's previous side of the triangle or
   fall back to face winding to choose a normal.
6. Refit the face BVH again if vertex/face contacts were collected.
7. **Optionally**, walk each unique structural edge against the same face
   BVH and consider the three edges of each nearby face. Canonical
   64-bit edge IDs avoid checking a pair twice. Skip edges sharing a
   vertex or within the structural one-ring, preserving ordinary cloth
   folds. Select the **two nearest distinct nonadjacent edges** in
   deterministic (distance, edge-key) order per source edge. All
   candidate edge pairs are gathered before any edge correction.
8. Apply an inverse-mass-weighted edge/edge position correction. The
   segment closest-point parameters provide linear endpoint weights.
   At exactly crossing edges the separating normal uses the segment
   cross product and their previous positions; collinear coincident
   edges fall back to a deterministic perpendicular. All-pinned edges
   and non-finite results are skipped.
9. Refit the face BVH again after edge corrections. Reconstruct particle
   velocities **after** both contact types, preventing spurious pops on
   subsequent steps.

## Bounded cost and memory

Avoiding a naive O(vertices * faces) full scan is critical. We reuse the
existing BVH (no new spatial index) and apply three strict budgets:

- at most **4 retained candidate faces per vertex**;
- at most **65,536 total stored contacts per step**;
- at most **128 face leaves inspected per vertex** and **1,048,576**
  total face leaves inspected per soft-body step;
- at most **2 closest edges per structural edge**, **32,768** total edge
  contact pairs per step;
- at most **128 candidate edges examined per source edge** and
  **1,048,576** total edge tests per soft body step.

A transient `LocalVector` stores pairs of 32-bit (vertex, face) IDs,
and another stores four 32-bit vertex indices per edge contact (bounded
to 512 KiB of payload, ignoring over-allocation). Both are reused
across frames. The unique structural edge list is allocated **only**
when edge contacts are enabled; both it and the adjacency hash table
are released when self collision is disabled or the mesh destroyed. There is
no extra hot-path ProjectSettings read. CPU/RAM can increase in enabled
mode, especially when many layers are packed closely; strict limits
prevent unbounded candidate storage or narrowphase leaf tests, but do
not guarantee a constant-time BVH traversal.

The finite candidate budget is a **quality/performance compromise**:
on scenes with extreme self-overlap it may skip some contacts. Sorting
by distance/edge key makes selection repeatable **for the candidates
that were visited**, but when the inspection budget is exhausted the
set of visited BVH leaves (and therefore selected contacts) can change
after BVH rebalancing. Do not assume every overlapping pair is
resolved in a single step, or that saturated scenes are bitwise
deterministic across tree rebuilds. Other structural constraints are
left unchanged.

## Physical limitations

- **Discrete only**: a vertex may tunnel completely through a triangle
  between steps. Fast/violent folds require a smaller timestep or
  future swept vertex-triangle CCD.
- Resolves **vertex vs triangle**, plus optionally **discrete edge
  vs edge**. Continuous swept edge-edge/vertex-triangle CCD, face-face
  interpenetration correction, and high-speed tunneling prevention are
  not yet supported.
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

# Fast standalone C++ header check (uses a test-only Vector3 stub,
# compiles the actual contact helper with GCC or Clang; not the engine).
g++ -std=c++17 -O2 -Wall -Wextra -Werror -pedantic \
  -Itests/stress/mock_physics -I. \
  tests/stress/physics_softbody_edge_standalone.cpp -o /tmp/cgame-edge-smoke
/tmp/cgame-edge-smoke

# Native helper regression (requires editor built with tests=yes)
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision triangle closest point covers all Voronoi regions"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision separates vertex from pinned triangle to thickness"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision mass weighting respects pinned vertices and compliant contacts"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision rejects invalid and degenerate triangles without mutation"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision edge pairs detect crossed segments with distant endpoints"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision finite segments handle skew and parallel edges"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision edge contact compliance and pinned particles"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Self-collision edge contact ignores degeneracy and invalid inputs"
```

The dedicated `.github/workflows/physics-softbody-self-collision.yml`
compiles the actual math header with GCC and Clang (a minimal test-only
Vector3 substitute), checks previous vertex/face math and exercises
20,000 seeded segment pairs. This checks C++ syntax and pure geometry,
**not** integration with Godot's real Vector3 or a built physics engine.
Both native C++ tests and full engine CI are still required.

Before merging, test a small folded cloth, a hanging pinned sheet, an
open sheet and a non-manifold triangle mesh under identical scene
conditions with self collision OFF, vertex-only and vertex+edge contacts ON.
Compare collision
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
