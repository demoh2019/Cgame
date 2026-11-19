# Cgame — topology-aware self edge–edge collision in Jolt

## Why this exists

Jolt currently provides native soft versus rigid-body contacts, but not
soft versus soft-body or soft self-collision (see Jolt Architecture).
Cgame already has experimental soft self vertex–face contacts and
separate soft–soft edge–edge contacts. Neither handles a **self-intersection
between two nonadjacent cloth edges**, when no particle is near any
opposing triangle.

Bullet's soft-body collision flags include VF_SS (vertex versus face),
CL_SS (soft cluster contacts) and CL_SELF (self-collision via clusters).
This patch adopts the geometric *principle* of collision against
non-neighboring elements; it copies no Bullet code and does not introduce
a full cluster or FEM solver.

## Enable

Project Settings > Physics > Jolt Physics 3D > Simulation:

- `soft_body_self_contacts = true` (existing master, default off)
- `soft_body_self_edge_contacts = true` (**new**, default off)
- `soft_body_self_contact_max_checks = 16384` (global per space and step)
- `soft_body_soft_contact_radius = 0.1` (contact thickness)
- `soft_body_soft_contact_recovery = 0.2` (velocity bias)
- `soft_body_soft_contact_friction = 0.2` (Coulomb coefficient)

This is independent of `soft_body_soft_contacts`, the toggle for
**different soft bodies**. All old projects retain their original path.

## Implementation

1. Reuse each body's sorted unique undirected triangle-edge keys from
   the self vertex–face topology pass; if that pass lacked budget, build
   the topology within the reserved edge-work quota.
2. For each **unordered edge pair** (i,j with i < j), reject pairs that
   share an endpoint or have endpoints connected by any mesh edge.
   This one-ring filter avoids repulsive impulses between ordinary cloth
   springs and adjacent triangles.
3. Check conservative expanded AABBs for the two segments.
4. Use the existing clamped Ericson closest-segment solver to get nearest
   points and interpolated segment weights s and t.
5. If distance is below the contact radius, compute effective inverse mass
   `(1-s)²inv_mA0 + s²inv_mA1 + (1-t)²inv_mB0 + t²inv_mB1`.
6. Compute a bounded normal velocity correction, and optional
   Coulomb-limited sliding friction, applying equal-and-opposite impulse
   shares to all four particle velocities **in the same local frame**.
7. Preserve pinned particles (inverse mass 0). Reject invalid/nonfinite
   inputs, degenerate segments and fully pinned contacts.

The pass runs before Jolt's parallel Update, using the same per-space
scratch buffer. With self-edge enabled, half the existing
`soft_body_self_contact_max_checks` budget is reserved for VF and half
for EE. Each considered edge pair decrements the EE budget (including
rejected adjacent pairs). Topology construction is charged when not
reused. Max face count remains 1024.

## Limitations

- This is **discrete** contact, not continuous self-edge CCD.
- Works on surface topology; seam vertices with distinct indices count
  as disconnected even if their positions coincide.
- Excluding one-ring neighbors also excludes legitimate extremely local
  folds. Nonadjacent folds can still tunnel when moving fast.
- No self edge BVH yet. Worst case is O(E²), bounded by the global quota.
  Dense meshes can exhaust the quota; valid contacts may be skipped.
- Contact is a pre-step **velocity impulse**, not XPBD positional
  projection, mesh tearing, volume FEM, or clustered self collision.
- There is no per-body toggle yet; it affects all active Jolt soft bodies
  when the project setting is enabled.
- C++ compilation, physical native simulation, FPS and RAM metrics remain
  unconfirmed until the native CI workflow passes.

## Tests

Reference tests, including topology, closest segments, momentum, settings
and source wiring:

    python3 -m unittest tests/stress/test_jolt_soft_self_edge_contacts.py -v

Native scene after building Cgame Jolt:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
      --path tests/stress/jolt_soft_self_edges \
      --script res://self_edges_regression.gd

The scene has one soft body containing **two disconnected crossing
triangles** whose endpoints are far from the other face, plus a
connected-quad control body. Both bodies have layer/mask zero, so
inter-body collision cannot contaminate the test.

Next optimization: spatial acceleration for edge pairs, persistent
adjacency cached per mesh and more demanding folded cloth benchmarks.
