# GodotPhysics 2D/3D: use cached shape inverse for point queries

## Problem and change

The built-in GodotPhysics `intersect_point()` implementation previously
calculated the inverse of the **composed** body and shape transforms
separately for every broadphase proxy candidate. In dense scenes or repeated
point picking, a matrix inverse is much more expensive than a pair of
cached matrix-vector transforms.

`GodotCollisionObject2D/3D` already stores:
- `get_inv_transform()`, the inverse of the body/area world transform;
- `get_shape_inv_transform(index)`, the inverse of that local shape transform.

These caches are maintained when a body/area moves or the local shape
transform changes; the same caches are already used by `intersect_ray()`.

For a world point `p`, with body transform `B` and local shape transform
`S`, the new point query computes

```cpp
const Vector3 local_point = object->get_shape_inv_transform(index).xform(
        object->get_inv_transform().xform(world_point));
```

instead of

```cpp
const Vector3 local_point = (B * S).affine_inverse().xform(world_point);
```

Algebraically, `(B * S)^-1 = S^-1 * B^-1`. This holds for translated,
rotated, scaled, sheared and other invertible affine transforms. Finite
precision means there may be small rounding differences near boundaries.

Both **2D and 3D** now use their existing caches, without adding memory
per body or changing the BVH, narrowphase, collision masks, or public API.
Filtering still occurs before the cached coordinate transforms are read.
This follows Jolt/Box2D's focus on minimizing expensive narrowphase work
after broadphase filtering, though the concrete cache use is based on
Cgame's own existing ray-query implementation.

## Test coverage

New native `tests/core/math/test_physics_point_cached_inverse.cpp` checks
512 transformed points per dimension with translations, anisotropic scales
and sheared bases. It compares composed affine inverse results with the
product of the independently computed inverses.

New `tests/stress/physics_point_cached_inverse_regression.gd` creates
256 static bodies **per dimension** with rotated parent transforms and
nontrivial local shape transforms. It verifies 32 rounds of point queries
(8,192 per dimension), collision mask and RID exclusion filtering, and
query correctness after both the body and local shape transform change.
Timings are reported as `query_us` and should be compared to an identical
baseline build on the same machine.

```bash
./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
  --path tests/stress \
  --script res://physics_point_cached_inverse_regression.gd
```

Independent numerical verification using 7,761 random invertible 2D
matrix pairs and 8,433 3D pairs found no difference exceeding 1e-10
in double precision. This checks algebra, **not** the Cgame runtime.

Full C++ compilation, Godot headless execution and performance measurement
remain necessary. The connected build host was offline at author time;
no FPS, RSS, or percentage speedup has been asserted.
