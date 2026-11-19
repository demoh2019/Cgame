# XPBD volume preservation for closed 3D soft bodies

This feature extends Cgame's existing optional **XPBD edge/distance**
constraint solver with an independently configurable **global enclosed
volume constraint** for deformable meshes. Its mathematical form follows
Extended Position-Based Dynamics (XPBD), and complements Jolt's tetrahedron
volume constraints and Bullet-derived soft-body simulation. This patch does
**not** introduce tetrahedral FEM or full fluid dynamics.

## Enabling it

Select **GodotPhysics3D** as the project's 3D physics engine. Under
Project Settings → Physics → 3D → Solver:

| Setting | Default | Behavior |
| --- | ---: | --- |
| `soft_body_xpbd_volume_preservation` | `false` | Enables global closed-volume projection |
| `soft_body_xpbd_volume_compliance` | `0.000001` | Volume constraint compliance; 0 gives the stiff/incompressible projection limit |
| `soft_body_xpbd_compliance` | `0` | Already existing **independent** edge/distance compliance; values above 0 enable compliant edge constraints |

Equivalent `project.godot` settings:

```ini
[physics]
3d/physics_engine="GodotPhysics3D"
3d/solver/soft_body_xpbd_volume_preservation=true
3d/solver/soft_body_xpbd_volume_compliance=0.000001
3d/solver/soft_body_xpbd_compliance=0.00001
```

Settings are cached in `GodotSpace3D` on world creation. To change them
for a world already running, recreate its physics space. Only the built-in
GodotPhysics3D backend is changed; the Jolt backend has its own soft-body
implementation.

## Correctness and limitations

- A global volume is well-defined only for a **closed, consistently
  oriented two-manifold triangle surface**. Each undirected edge must
  belong to exactly two triangles with opposite directions. Degenerate
  edges, boundary edges, non-manifold edges, inconsistent winding, zero
  or non-finite signed rest volume automatically disable this constraint.
  Degeneracy uses a **relative scale-aware volume tolerance**, so a small
  but nondegenerate closed tetrahedron is not incorrectly classified as open.
  **Open cloth meshes remain unaffected**.
- Before the first volume solve after a mesh/repose update, validate mesh
  topology and capture signed rest volume from the positions *before*
  the simulation step. The validation is lazy and occurs only when the
  setting is enabled; normal cloth and legacy soft bodies avoid the
  topology-map allocation.
- Each XPBD substep computes signed volume and its per-particle
  gradients using the current triangle mesh. The scalar constraint is
  `C = V_current - V_rest`; with `alpha_tilde = compliance / dt²`, solve
  `delta_lambda = -(C + alpha_tilde * lambda) / (sum_i inv_mass_i * |gradient_i|² + alpha_tilde)`.
  Then adjust each movable vertex by `inv_mass_i * gradient_i * delta_lambda`.
- Reset the scalar multiplier to zero **at every physics step**, while
  retaining it across solver iterations within that step. This avoids
  carrying stale constraints between unrelated steps.
- Inverse-mass-zero (pinned) vertices remain fixed. All-pinned and
  degenerate constraints are skipped, with checks for non-finite
  correction terms. Gradient norms are accumulated in double before
  conversion to real_t; a proposed correction is validated for **all**
  movable vertices before any position or multiplier is committed.
- Volume solve is interleaved with whichever existing edge solver the
  world uses: XPBD distance or Bullet-derived PBD. It can be enabled
  independently of edge compliance. Wind, gravity, pressure, collision,
  bending links, damping, shrinking and existing node velocities are
  not removed. The newer **XPBD triangle-area** constraint and opt-in
  **viscoplasticity** are both preserved and interleaved in the same solver.

Volume preservation is **not** pressure. Pressure applies outward forces
that may change the rest volume; XPBD resists volume deviations.
For multiple disconnected closed shells the constraint preserves the
*sum* of signed volumes, not each disconnected shell individually.
Self-intersecting meshes with manifold edges can still have ambiguous
physical interiors; use clean, consistently oriented input geometry.

## Performance

The baseline setting is OFF, preserving the old solver and its
per-soft-body memory. In the enabled mode, the extra work per solver
iteration is **O(number of triangles + number of physical vertices)**.
One per-vertex gradient buffer is reused; mesh topology is checked only
on first use after a reset, never per contact or per iteration.

This is a complex accuracy feature, **not a speedup**. Expect greater
CPU cost for high-poly closed meshes. Decreasing mesh triangle count,
reducing iteration count and benchmarking with identical physics ticks
is recommended before adopting in production.

## Validation

```sh
# Python wiring and safety contracts.
python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_volume.py' -v
python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_volume_numeric.py' -v

# Native C++ numerical regression (requires a Cgame editor built tests=yes).
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] XPBD enclosed tetra volume and gradients are translation invariant"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] XPBD soft volume moves movable particles toward rest volume"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] XPBD volume compliance softens correction and avoids singular pinned meshes"
```

Run native soft-body scenes with a tetrahedron, UV sphere, open cloth, a
torn/non-manifold mesh, pin/unpin, stretching and wind. Record position
stability, NaNs, volume drift, median/p95 physics-step time and RAM.

Sources: [original XPBD implementation](https://github.com/InteractiveComputerGraphics/PositionBasedDynamics/blob/master/PositionBasedDynamics/XPBD.cpp),
[Jolt's soft-body architecture](https://jrouwe.github.io/JoltPhysics/),
and [XPBD formulation](https://scikit-shapes.github.io/scikit-shapes/explanation/deformation_models/xpbd.html).
