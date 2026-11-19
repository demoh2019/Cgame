# GodotPhysics3D XPBD self-collision: robust scale-independent vertex/face geometry

This patch strengthens the existing SoftBody3D discrete vertex/triangle
self-collision projection and its optional Coulomb-limited tangential friction.

## Previous numerical limitations

The old narrowphase constructed `ab = b-a`, `ac = c-a` and
`ab.cross(ac).length_squared()` using `real_t`. Under the common float32
build, even legitimate finite triangle vertices could:

- overflow the cross product or squared norm (e.g., triangle sides around
  `1e20` world units), silently disabling the contact;
- have a valid tiny area discarded by the fixed `CMP_EPSILON²` threshold
  (e.g., edges around `1e-8`);
- suffer cancellation in the Gram determinant `d00*d11-d01*d01`, losing
  barycentric precision on long, thin triangles;
- partially overwrite output normal or distance even when the projected
  point later failed the interior-triangle test.

These problems affect the regular XPBD vertex/face contact AND the new
self-contact friction because both reuse the shared projection routine.

## Wide, scale-invariant narrowphase

- Subtract each input coordinate in `double` before forming edges.
- Compute the normal and normal squared magnitude in `double`, and reject
  non-finite intermediate lengths.
- A triangle is considered nondegenerate when
  `|ab×ac|² > 1e-20 * (|ab|² * |ac|²)`. This test is relative to the
  triangle's shape and invariant under uniform scaling.
- Compute barycentric weights using `|ab×ac|²` directly as the Gram
  determinant instead of subtracting nearly equal squared dot products.
- Apply the previous strict triangle-interior criteria unchanged. No
  new proximity contacts are generated outside the triangle.
- Stage normal, barycentric weights and signed plane distance in local
  temporaries, then publish them together after all finite/range checks.

The original normal contact and friction use the same helper, so neither
needs a new collision traversal or per-frame allocation.

This is not a remedy for precision already lost when **two distinct world
coordinates become equal in float32**; enable `precision=double` or
origin-shifting for very distant, very small objects. It also does not add
edge/edge friction or continuous collision detection.

## Verification

```bash
python3 -m unittest discover -s tests/stress \
  -p test_physics_xpbd_self_collision_scale.py -v

# Native C++ test requires tests=yes:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[PhysicsSelfCollisionScale]"
```

Six new native C++ scenarios cover large/small valid triangles, reversed
winding, nearly collinear faces, atomic failure, and a high-scale actual
self-contact correction. Six Python tests check source contracts and
randomized float32-scale barycentric calculations. Compare a native
float32 build against double precision with folded cloth scenes before
claiming runtime robustness or performance improvement.
