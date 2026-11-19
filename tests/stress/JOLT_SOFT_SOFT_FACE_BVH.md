# Cgame Jolt: bounded BVH for deforming soft-soft face contacts

## Why

Bullet Physics maintains dynamic face and node AABB trees (DBVT) for its
soft-body collision path. Cgame's experimental Jolt vertex-face mode previously
enumerated every triangle for every vertex. While the exact solver already
used per-face AABB rejection, the test budget was exhausted by distant faces.

This revision adds an **opt-in** per-body-pair median-split face BVH built
from the soft body's **current deformed vertices**. It is recomputed
before a contact direction's tests, retaining correct bounds as the soft
surface deforms. The same closest-point, inverse-mass/barycentric impulse,
two-way response and friction code is reused.

## Settings

Set under `physics/jolt_physics_3d/simulation/`:

- `soft_body_soft_contacts = true` (master, default false)
- `soft_body_soft_vertex_face_contacts = true` (VF, default false)
- `soft_body_soft_vertex_face_bvh = true` (new acceleration, default false)

All three are needed to select the accelerated path. Legacy VV/VF code
remains the fallback. Meshes with fewer than 32 or more than 4096 faces,
or insufficient work budget, use the original linear VF search.

## Algorithm

For one ordered body pair:

1. Validate a face count of 32..4096.
2. Charge a conservative O(F log F) build budget, then compute per-face
   world-relative bounding boxes with finite-input checks.
3. Split at median triangle center on the longest box axis; create four-face
   leaves, making tree depth O(log F) even for coplanar triangles.
4. For each point, traverse the tree against its contact-radius AABB.
5. Only issue exact closest-triangle tests for candidate leaves.
6. Charge global budget for tree-node visits **and** exact tests. When the
   budget runs out, skip subsequent candidates for the current frame.

Two body directions build independent face trees because the surface of
either soft body may be the sparse mesh. Only the face-index ordering changes:
the physical impulse response is identical to the previous VF method.

The tree uses Jolt arrays and a median selection; no extra memory is
allocated when acceleration is disabled. When enabled, four Jolt scratch
arrays are **reused across both query directions and all soft-body pairs**
within one simulation pre-step, avoiding per-pair allocator churn.
Scratch retains the peak O(F) capacity for that step and is released
at the end of the step.

### Limits

This is not a persistent tree: repeated builds cost O(F log F) each step and
may not beat brute force for small or densely overlapping meshes. It
limits the number of contact evaluations to the existing global
`soft_body_soft_contact_max_particle_pairs` budget (default 32768).
Face BVH construction and traversal count against that budget too.
Other existing limits remain in force: max 2048 body candidates per step,
and up to 65536 total user-configurable work units per step.

The BVH is conservative and **does not miss a triangle** when its AABB
intersects the point's radius box, provided the global budget has room.
When budget is exhausted, the simulation can skip some contacts. This
is deliberate backpressure rather than a false-negative geometric test.

## Validation

Source, mathematical and BVH reference tests:

    python3 -m unittest tests/stress/test_jolt_softsoft_face_bvh.py \
        tests/stress/test_jolt_soft_soft_vertex_face.py \
        tests/stress/test_jolt_soft_soft_particle_contacts.py -v

Native physics simulation (needs built Cgame editor with Jolt):

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
        --path tests/stress/jolt_soft_soft_bvh \
        --script res://bvh_regression.gd

The native scene uses a deforming 8×8 grid (98 triangles), a tetrahedral
soft-body tip, and a separate collision-masked control pair. Compare
the same geometry with BVH off and on for step time and peak RSS.

## Remaining work

This does not provide continuous collision detection (CCD), self-collision,
edge-edge contacts, persistent BVH refitting, clusters, contact manifolds,
or full FEM. The next step is swept motion queries/CCD, followed by
refittable per-object face trees and wider performance benchmarking.

Use native CI to confirm C++ compilation and physics correctness;
source-level mathematical checks alone are not sufficient.
