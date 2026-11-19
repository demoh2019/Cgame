# Cgame: opt-in soft-body convex volume preservation (Jolt)

Jolt already exposes per-tetrahedron volume constraints (an XPBD/PBD-style
position constraint), but Cgame previously created only triangle-surface
stretch, bend, and optional LRA constraints.

Cgame now has a **CPU-compatible approximate volumetric soft body** path for
small **closed convex** surface meshes. This is NOT FEM and does not supply
material stress/strain tensors, plasticity, fracture, FEM collision meshes,
or independent tetrahedral import.

## How it works

After the normal Jolt surface constraints are generated:
1. Validate finite positions and reject invalid/degenerate triangles.
2. Require every undirected edge exactly twice, with opposing orientation.
3. Require every surface vertex to be on the same side of every triangle's
   supporting plane as the mesh centroid (convexity/centroid-inside test).
4. Add one *interior* particle at the mean of the physics vertices.
5. Create one tetrahedral volume constraint per surface triangle.
6. Calculate rest volumes and run Jolt's constraint optimizer.

This star tetrahedralization is only correct for **convex** closed surfaces.
Concave/open/nonmanifold meshes are skipped rather than generating invalid
constraints. For bounded setup and memory the maximum is 2048 physics
vertices and 4096 surface triangles.

## Settings

Project Settings > Physics > Jolt Physics 3D > Simulation:

- `soft_body_volume_preservation = false` (default off).
- `soft_body_volume_compliance = 0.00001` (nonnegative finite value).
  Lower values penalize volume changes more strongly; 0 is rigid-volume
  constraint.

Settings are read during soft-body creation. To update an existing body's
tetrahedral layout, recreate the body/mesh. When the mode is off, the fan
validation and extra particle/constraints are never created.

The additional vertex is invisible, but it participates in soft-body mass
distribution and the physics solver. This changes the body's behavior
when the mode is enabled. Closed mesh winding must be consistent.

## Validation

Python math/topology/source contracts:

    python3 -m unittest tests/stress/test_jolt_softbody_volume.py -v

Native regression (requires a compiled Cgame editor with Jolt):

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
        --path tests/stress/jolt_volume \
        --script res://convex_volume_regression.gd

The native test includes a closed tetrahedron under gravity/impulse and
an open two-triangle cloth mesh to exercise the fallback. It checks
finite vertex positions, bounds and noncollapsed tetra volume.

Benchmarks should compare identical Jolt scenes with the feature disabled
vs enabled, tracking CPU/frame time, peak RSS and numerical stability.
The initialization convexity validation is O(vertices * faces), bounded
by input limits. Every enabled tetra fan adds one interior physics particle
and one volume constraint per face.

## Limitations and next steps

- Does not handle arbitrary concave soft-body meshes or imported FEM
  tetrahedral meshes.
- Does not add GPU FEM, tissue material models or fracture mechanics.
- Internal particle collisions and interactions may differ from surface-only
  cloth, so collisions with rigid bodies must be benchmarked.
- Next step: tetrahedral import/mesh preprocessing, per-element material
  behavior and native performance regression.
