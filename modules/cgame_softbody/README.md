# Cgame Softbody (experimental)

Native soft-body simulation for the Cgame Godot fork. It is a C++ port of the reference GDScript implementations (`scripts/shared/xpbd_cloth.gd`, `scripts/shared/xpbd_rope.gd`, `scripts/client/hair_strands.gd`) with identical behaviour and API names, plus a scene node that renders cloth efficiently.

## Classes

| Class | Base | Purpose |
| --- | --- | --- |
| `CgameXPBDCloth` | `RefCounted` | XPBD cloth grid: stretch/shear/bend constraints, sphere/capsule/plane colliders, spatial-hash self-collision, tearing, `build_mesh()` |
| `ClothInstance3D` | `MeshInstance3D` | Steps a cloth in `NOTIFICATION_INTERNAL_PHYSICS_PROCESS`, follows `Skeleton3D` bones, streams vertices with `RenderingServer.mesh_surface_update_vertex_region` |
| `CgameXPBDRope` | `RefCounted` | XPBD rope: distance/bend constraints, sphere/plane colliders, segment self-collision, knot heuristic |
| `CgameHairStrands` | `RefCounted` | Guide-strand hair (shape matching + Follow-The-Leader), capsule collision, render-strand interpolation, LOD, culling, native ribbon mesh generation |

## Differences to the GDScript versions

- `CgameXPBDCloth.drive(index, world_pos)` and `CgameXPBDRope.drive()`: pin a particle to a position that is updated each frame without a `Callable`; the particle glides across the sub-steps. `ClothInstance3D` uses this for bone attachments.
- `CgameHairStrands.build_ribbon_mesh(per_guide, seed, width)` generates render strands and the ribbon mesh in one native pass.
- Hair and rope fields that were public GDScript variables are exposed as properties (tunables) or getters (`get_pos()`, `get_rest()`, ...).
- `ClothInstance3D` uses in-place vertex updates when the surface is plain (float positions, octahedral normals); tearing or unusual layouts trigger a rebuild.

## Usage

```gdscript
var cloth := CgameXPBDCloth.new()
cloth.setup_grid(20, 20, 0.05, Transform3D(Basis(), Vector3(0, 2, 0)))
for i in cloth.columns():
    cloth.pin(cloth.index_of(i, 0), cloth.positions()[cloth.index_of(i, 0)])

var node := ClothInstance3D.new()
add_child(node)
node.set_cloth(cloth)
```

`game_facade/cgame_softbody_facade.gd` picks the native classes and falls back to the GDScript reference files when the module is not compiled in.

## Credits

- Macklin, Muller, Chentanez, "XPBD: Position-Based Simulation of Compliant Constrained Dynamics" (2016).
- Matthias Muller, "Ten Minute Physics" (https://github.com/matthias-research/pages, MIT License), structure of the small-steps cloth and rope solvers.
- Muller, Kim, Chentanez, "Fast Simulation of Inextensible Hair and Fur" (VRIPHYS 2012), Dynamic Follow-The-Leader.
- AMD TressFX (MIT License) concepts for shape matching and guide interpolation.
- Ericson, "Real-Time Collision Detection", closest points between segments.

All code is a clean re-implementation from the published algorithms.

## Tests

Doctests live in `tests/test_cgame_softbody.h` (pinned cloth, sphere collision, tearing, rope length, hair segment lengths and capsule collision, ribbon mesh). Run with `scons tests=yes` and `bin/godot --test --test-case="*CgameSoftbody*"`.
