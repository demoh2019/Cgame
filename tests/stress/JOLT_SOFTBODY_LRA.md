# Advanced cloth physics: Jolt long-range attachments (LRA)

Cgame already has Jolt soft bodies, stretch/shear XPBD, optional distance and
dihedral bending, and face-normal aerodynamic drag. This change enables
Jolt's existing LRA system to limit stretch relative to **pinned mesh
vertices**. It does not embed Bullet, PhysX or third-party code.

## Settings

Project Settings > Physics > Jolt Physics 3D > Simulation:

- `soft_body_lra_mode`: Disabled (0, default), Euclidean (1), Geodesic (2).
- `soft_body_lra_max_distance_multiplier`: 1.05 by default, clamped to
  [1, 10]. A value of 1.05 allows 5% extra distance to an anchor.

A higher multiplier allows more stretch/slack. LRA constraints are
generated only when opt-in is enabled and there is at least one valid
pinned physics particle. With mode 0, no LRA-specific vertex scan or
constraints run, preserving the previous default performance.

Mode 1 connects particles to the nearest kinematic anchor using straight-
line rest distance. Mode 2 computes geodesic distance through the mesh
edge graph, preserving intended length around folds and obstacles. Jolt
uses a shortest-path/Dijkstra-style traversal during construction.
The geodesic setup may require more CPU and memory than simple Euclidean
distance; benchmark at multiple mesh sizes.

**Important**: The LRA constraint graph is generated at body creation.
Pin points before assigning the body to a physics space (or via editor
scene properties before entering the world). Pinning/unpinning after
creation updates particle mass but does **not** rebuild the LRA graph;
recreate the body to adopt new anchor topology. This limitation avoids
expensive physics rebuilds during every animated attachment update.

## Related bug fix

The Jolt backend deduplicates coincident visual mesh positions into
physics particles. Earlier checks asked whether a *physics* index was in
a set of *visual mesh* pin indices. That produced inconsistent results
for welded visual aliases. Pin-state queries and per-vertex impulses now
check the actual physical inverse mass, making both aliases consistent.

## Checks

Mathematical + source contract suite:

    python3 -m unittest tests/stress/test_jolt_softbody_lra.py -v

Native test (requires a compiled Cgame Jolt editor):

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
        --path tests/stress/jolt_lra \
        --script res://pinned_cloth_lra_regression.gd

The fixture creates a 12×12 pinned cloth with a duplicated *referenced*
visual vertex, enables geodesic LRA, and verifies finite coordinates,
bounds, and fixed aliases under simulation. It does not establish FEM
accuracy or fluid-structure coupling. The Python suite validates
configuration, API wiring, default-off behavior, alias checks, and a
folded-mesh geodesic reference case.

Track release build CPU/frame, peak resident memory and constraints for
pinned 16×16, 64×64 and 128×128 meshes, each in three modes. Do not
claim a performance improvement without a matching baseline.
