# Swept edge/edge CCD for GodotPhysics3D soft bodies

## Gap and comparison

Current `develop` already implements optional XPBD cloth stretch, triangle
area, dihedral bending, volume preservation, tethers, vertex/face
self-collision, **vertex/face swept CCD**, and discrete edge/edge collision.

Jolt's soft bodies include triangle edge/volume/hinge constraints; robust
feature-pair CCD is studied by Brochu et al. and by PositionBasedDynamics.
One missing case in Cgame is a **moving interior edge/edge intersection**
where the two edges are far apart both before and after the frame.
Existing edge self-collision checks only final positions and misses it.

This branch extends the existing GodotPhysics3D edge BVH and XPBD solver;
it does **not** add another physics engine or replace the mature Jolt
backend. It makes the already-present world-level
`soft_body_self_collision_ccd` flag also cover swept *edge/edge* collisions
when `soft_body_self_collision_edge_edge` is enabled.

## Enabling

In Project Settings -> Physics -> 3D -> Solver, with GodotPhysics3D:

```ini
[physics]
3d/physics_engine="GodotPhysics3D"
3d/solver/soft_body_self_collision_thickness=0.02
3d/solver/soft_body_self_collision_edge_edge=true
3d/solver/soft_body_self_collision_ccd=true
```

All relevant features are **off by default**. The existing CCD flag
already applies to vertex/face; with edge/edge disabled, it continues to
mean vertex/face only. The legacy discrete edge/edge solver is retained
unchanged if CCD is off. Settings are cached per `GodotSpace3D` world.

## Geometry and constraints

For linearly moving endpoints `a(t), b(t), c(t), d(t)` of two finite
edges, their coplanarity determinant is

```
F(t) = dot(d(t)-a(t), cross(b(t)-a(t), c(t)-a(t)))
```

`F(t)` is a cubic polynomial. The new no-allocation helper
`servers/physics_xpbd_edge_ccd.h` computes coefficients, splits the
unit interval at the roots of the quadratic derivative, then brackets
each **transversal sign-changing** root and bisects it 28 times.

A root is a *candidate*, not yet a collision. At the candidate time,
run Cgame's existing `physics_xpbd_closest_edges` on the finite
segments. This rejects endpoints, parallel/degenerate geometry and
infinite-line false positives. The impact witness contains the
earliest valid time, the two segment barycentric coordinates and
an oriented normal based on the original side.

For accepted contacts:

1. The already-existing **edge BVH** is refit with each edge's
   before-step `q` and current `x` endpoints. Queries likewise use
   swept AABBs. There is no second spatial index.
2. Existing topological one-ring rejection, unique-index pair selection,
   inverse-mass pin checks, per-edge and global contact ceilings still
   apply. A separate **8192 root-tests-per-soft-body-step** limit
   prevents pathological folds from creating unbounded cubic solving.
3. Discrete contacts use the old solver. Only pairs not already in
   discrete contact are tested for a swept crossing.
4. Gather all witnesses BEFORE moving vertices. Keep the minimum impact
   time for each participating physical node in an optional reusable
   `LocalVector<real_t>`. Rewind **only movable nodes**, slightly
   before first impact; pinned nodes never move.
5. Solve the optional swept XPBD row with its **fixed impact-time**
   barycentric parameters and oriented normal, using nonnegative
   Lagrange multipliers, `alpha=compliance/dt²`, and inverse masses
   of all four endpoints. This avoids the old discrete solver's
   post-tunneling closest-point early-out.
6. Restore usual vertex velocities in the parent solver from corrected
   positions. Existing face BVH refit for ray/shape queries is unchanged.

No extra CCD contact storage is allocated or retained in discrete-only
worlds, and all optional buffers are freed on topology rebuild or
soft-body destruction.

## Costs, safety and limitations

- In CCD-enabled worlds, both old and current endpoints inflate the edge
  BVH bounding boxes. This increases false-positive candidate queries,
  and calculating cubic roots is more expensive than discrete closest
  points; it is a **quality feature, not a performance speedup**.
- Root solving per candidate is fixed to at most 28 bisection iterations
  over up to 3 monotone intervals. Up to 8192 expensive CCD pairs per
  soft-body step are attempted.
- This detects **transversal coplanarity crossings** of two nonparallel
  finite edge interiors under linear endpoint motion. Grazing/tangent
  contacts (even multiplicity), persistently coplanar intersections,
  parallel edges and endpoint-only collisions are not new CCD cases.
  Existing discrete vertex/face or edge/edge solvers may handle some of
  them, but this code does not guarantee intersection-free motion.
- A nonlinear cloth trajectory within one physics step is approximated
  by the linear path between pre-step and post-material positions.
  Rewinding to the first impact can change the satisfaction of other
  XPBD stretch, bending and volume constraints. Large collisions can
  require smaller simulation steps or more outer iterations.
- The per-edge shortlist stops after the configured candidate count;
  selection in saturated scenes can depend on BVH traversal order.
  CCD budget exhaustion can still permit tunneling. Very large
  coordinates, nearly parallel lines and degenerate geometry have
  conservative rejection guards.
- This is not volumetric tetrahedral FEM, exact nonpenetration CCD,
  cloth tearing, inter-soft-body contact or fluid simulation.

## Validation

```bash
# Python structural and default-off/opt-in wiring tests
python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_edge_ccd.py' -v

# A fast independent C++17 syntax + numerical smoke, not the full engine
g++ -std=c++17 -O2 -Wall -Wextra -Werror -pedantic \
  -Itests/stress/mock_xpbd_edge_ccd -I. \
  tests/stress/physics_xpbd_edge_ccd_standalone.cpp -o /tmp/cgame-edge-ccd
/tmp/cgame-edge-ccd

# Requires a full native Cgame build with tests=yes
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Swept edge-edge CCD catches a fast crossing with distant final endpoints"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Swept edge-edge CCD rejects non-crossing, parallel and infinite-line contacts"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Swept edge-edge CCD is translation and common-velocity invariant"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Swept edge XPBD projection is pin-safe and rejects invalid witnesses"
```

Before merging into `develop`, compare matched 2D/3D project physics
scenes with CCD OFF and ON; run existing Cgame vertex/face self-collision
tests, an actual fast-fold cloth scene, stability and NaN checks, p50/p95/p99
physics-step duration, peak RSS and allocator churn. A native C++ build
of GodotPhysics3D, not only the standalone helper, is mandatory.

### References

- Jolt Physics: https://jrouwe.github.io/JoltPhysicsDocs/5.7.0/class_soft_body_shared_settings.html
- PositionBasedDynamics XPBD: https://github.com/InteractiveComputerGraphics/PositionBasedDynamics/blob/master/PositionBasedDynamics/XPBD.h
- Geometrically exact CCD (different and stronger than this bounded implementation):
  https://www.research.autodesk.com/publications/efficient-geometrically-exact-continuous-collision-detection/
