# XPBD dihedral bending for GodotPhysics3D soft bodies

This patch adds **true adjacent-triangle dihedral-angle constraints** for
cloth and thin deformable surfaces, following the design of Jolt Physics
`SoftBodySharedSettings::DihedralBend` and the XPBD formulation.

The existing GodotPhysics3D soft-body implementation already supports:
distance-spring bending links (two-hop graph links), XPBD distance,
XPBD surface area, and (on current develop) experimental volume
preservation. **Dihedral bending is different:** it resists rotation of
two triangles around their common edge instead of approximating bending
through the distance between second-neighbor particles. It therefore
allows independent fold resistance when a surface stretches.

## Project setting

```ini
[physics]
3d/physics_engine="GodotPhysics3D"
3d/solver/soft_body_xpbd_dihedral_compliance=0.00001
```

`physics/3d/solver/soft_body_xpbd_dihedral_compliance` is **0.0
(default)**, disabling all hinge construction and solving. A positive
finite value enables the constraint. Higher compliance produces softer
fold resistance. The solver caches this setting once per physics space;
an already-running world must be recreated to pick up changes.

This feature affects **only GodotPhysics3D soft bodies** (not rigid body
joints, 2D physics or Jolt's separate backend). When disabled it adds no
hinge memory and does no new per-step mesh traversal.

## Hinge topology and memory

- Build an unordered edge map only on the first *enabled* solver step
  for a mesh. For each edge, accept exactly two adjacent triangles with
  reversed directed edge winding and **four distinct vertices**.
- Ignore boundary edges, non-manifold edges shared by 3+ triangles,
  degeneracy, bad winding and coincident opposing vertices.
- Preserve deterministic mesh insertion order with an auxiliary edge
  order vector during construction, rather than iterating hash buckets.
- The expensive hash map and edge order list are transient and discarded
  after construction. Each retained hinge is four 32-bit vertex IDs, a
  rest angle and an accumulated multiplier (~24 bytes in single-precision
  builds, ~32 bytes in double-precision builds).
- Capture the rest angle from each physical node's source/rest position
  rather than from positions that have already been displaced by gravity.
  Rebuild after a mesh or base-rest-state reset. Free storage when the
  soft body is destroyed or moves to a space where bending is disabled.
- No per-iteration heap allocations; only reuse indexed hinges.

## Mathematics

For shared edge `e = b - a`, incident triangles use consistently
oriented normals

```
n1 = normalize(cross(e, c - a))
n2 = normalize(cross(d - a, e))
angle = atan2(dot(normalize(e), cross(n1, n2)), dot(n1, n2))
```

Unlike unsigned `acos(dot(n1,n2))`, this signed `atan2` hinge angle
has a well-defined nonzero derivative at a perfectly flat crease.

The XPBD constraint is `C = wrap(angle - rest_angle)`, with
`alpha_tilde = compliance / dt^2`. Accumulate one multiplier per hinge
**across iterations of one physics step**, and clear all multipliers at
the beginning of the next step:

```
delta_lambda = -(C + alpha_tilde * lambda) /
               (sum_i inv_mass[i] * length_squared(gradient[i]) + alpha_tilde)
position[i] += inv_mass[i] * gradient[i] * delta_lambda
```

Analytical gradients are evaluated directly from the edge and two
unnormalized triangle normals. No finite-difference work in the
runtime; tests use numerical differentiation to verify the derivation.

Both incident triangles and their common edge must have finite,
nonzero area/length. All-pinned hinges, invalid compliance and any
non-finite projected positions are ignored rather than corrupting
soft-body state. The closed-volume XPBD constraint remains independent.

## Limitations and profiling

This is an experimental complex-physics feature, **not an automatic
performance optimization**. Solving an additional hinge costs O(number
of interior edges) per solver iteration, including atan2 and normal
construction. On large dense cloth meshes this can increase CPU work,
although its compact indexed representation minimizes persistent RAM.

The existing two-hop spring bending links are still present, so the two
forms of bend resistance act together when this feature is enabled.
Do not interpret the resulting compliance as an isolated dihedral-only
cloth constitutive model. Angle rest state is based on the source mesh;
very large nonuniform runtime scale changes require care. No tearing,
topology mutation, self-collision, FEM continuum or particle fluid
simulation is added in this PR.

## Tests

```sh
# Source and wiring contracts (independent of native build)
python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_dihedral.py' -v

# Build Cgame editor with tests=yes, then:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] XPBD dihedral flat fold and analytical angle gradients"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] XPBD dihedral resists folding and preserves pinned hinge endpoints"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] XPBD dihedral compliance reduces fold correction"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] XPBD dihedral handles degeneracy, all-pinned and invalid compliance"
```

Native tests verify flat-fold derivatives, all 12 analytical gradient
components against central finite differences, fold recovery, compliance
sensitivity, pinned endpoints, coincident-edge and zero-area safety.
Still required: a headless real-world soft-body regression for open cloth,
multiple sewn seams and a 3+ triangle non-manifold edge, then on-device
physics-step p50/p95, RAM and determinism comparisons against develop.

References:
- Jolt dihedral bend:
  https://jrouwe.github.io/JoltPhysicsDocs/5.7.0/struct_soft_body_shared_settings_1_1_dihedral_bend.html
- Open-source XPBD implementation:
  https://github.com/InteractiveComputerGraphics/PositionBasedDynamics/blob/master/PositionBasedDynamics/XPBD.cpp
- XPBD method:
  https://developer.blender.org/docs/features/nodes/xpbd_solver/xpbd_method/
