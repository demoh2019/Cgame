# Cgame — topology-aware self-collision for Jolt soft bodies

## What is new

Official Jolt Physics documentation currently says soft bodies collide
with rigid bodies, but it does not implement soft-body versus soft-body
contacts or soft-body self-collision. Bullet exposes soft-body
vertex-face and cluster self-collision flags, while PhysX offers a
GPU-based FEM deformable surface and volume simulation.

This change adds a **CPU, vertex-versus-deforming-triangle self-collision**
pass to Cgame's Jolt backend. It can keep folded, non-neighboring sections
of a cloth mesh from collapsing through each other. No Bullet or PhysX
implementation was copied, and this is not full FEM or continuous
self-collision detection.

## Configuration

In Project Settings → Physics → Jolt Physics 3D → Simulation:

- `soft_body_self_contacts = false` (new; disabled by default).
- `soft_body_self_contact_max_checks = 16384` (new; 1024..65536
  per **space and step**, shared by all active self-colliding soft bodies).
- `soft_body_soft_contact_radius = 0.1` metres (existing).
- `soft_body_soft_contact_recovery = 0.2` (existing).
- `soft_body_soft_contact_friction = 0.2` (existing).

Self-collision is **independent** of the `soft_body_soft_contacts`
master toggle for *different* soft bodies. It works even when collision
layers and masks disable cross-body collisions, because the contact is
between parts of the **same** soft-body mesh.

## Contact algorithm

1. Collect current triangle edges, canonicalize as unsigned 64-bit
   (minimum vertex ID, maximum vertex ID), sort and deduplicate.
2. Debit the global self-collision budget for topology construction:
   a conservative O(F log F) bound.
3. Skip meshes with more than 1024 faces; for 32–1024 faces build the
   existing 4-face-leaf BVH from the **current local vertex positions**.
   Charge BVH building against the same budget. Small meshes use a
   cheap linear scan.
4. For each surface vertex, query candidate triangles within the contact
   radius. **Reject** any triangle containing that vertex or connected
   to it by an edge to any of the triangle's corners. This 1-ring
   exclusion prevents neighboring cloth springs and adjacent faces
   from being mistakenly treated as contacts.
5. For nonlocal triangles, find the closest face point with the
   existing seven-region point-to-triangle algorithm.
6. For barycentric weights u,v,w and inverse masses, use the effective
   mass `m^-1_vertex + u²m^-1_a + v²m^-1_b + w²m^-1_c`.
   Apply equal-and-opposite momentum-preserving normal impulses and
   Coulomb-limited tangential friction **within the same body**.
7. Pinned particles with zero inverse mass remain fixed. Invalid,
   degenerate, nonfinite and all-pinned candidates are skipped.
8. Stop when the shared per-step self budget is exhausted. All BVH
   node visits and candidate tests consume budget.

The pass runs before Jolt's parallel `Update()`; particle velocities
are therefore modified synchronously. It uses no allocations when
disabled and reuses Jolt scratch buffers across active soft bodies.

## Limitations and safety

- This is *discrete* vertex–face self collision, not full continuous
  collision detection. Fast folds can still tunnel between steps.
- Direct one-ring connected vertices are excluded. This avoids false
  contacts around cloth edges but also means small local folds
  involving directly connected triangles will not repel each other.
- The global budget makes overloaded scenes order-dependent. Large
  or dense meshes may consume the budget during topology construction;
  above 1024 faces self collision is skipped, rather than allowing
  uncontrolled O(N²) CPU use.
- A face BVH is rebuilt every step; a cached and refittable BVH plus
  immutable adjacency structure would further reduce CPU cost.
- No edge–edge **self** contacts, persistent collision manifolds,
  position-level XPBD contact projection, tearing, or exact FEM.
- Project-wide setting currently applies to all active soft bodies;
  per-body opt-in is not yet exposed.
- This is experimental; do not ship enabled by default until C++
  compilation, simulation stability and actual FPS/RAM testing pass.

## Testing

Independent topology, momentum and source checks:

    python3 -m unittest tests/stress/test_jolt_soft_self_contacts.py -v

Headless Cgame native Jolt physics scene:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress/jolt_soft_self \
      --script res://self_collision_regression.gd

The native fixture has two disconnected triangle sheets that start
0.055 m apart within **one soft body**, plus a second body containing
two adjacent triangles. It tests separation of the nonlocal sheets,
absence of false adjacency repulsion, pinned vertices, finite bounds
and finite particle positions.

As with other recent Cgame Jolt additions, code and Python reference
checks alone do not prove a successful native build or physical response.
