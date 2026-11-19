# Closed SoftBody3D volume: relative scale and safe gradients

This patch **hardens the XPBD closed-surface volume solver already present in
Cgame develop**. It does not add a second volume constraint, second solver, or
new ProjectSettings. The existing opt-in
`physics/3d/solver/soft_body_xpbd_volume_compliance` still controls volume
preservation; 0 disables it.

## Fixes

**Scale-relative degeneracy.** A tetrahedron of side 1 mm encloses
`1.6667e-10 m³`. The former absolute `CMP_EPSILON` threshold discarded this
valid closed soft body. Now the engine compares
`abs(signed_volume / (maximum_coordinate_extent ** 3)) > 1e-10`.
This dimensionless condition is uniform-scale invariant and continues
rejecting zero-volume, flat or non-finite geometry. The reference signed
volume uses the existing double-precision translated-world formulation.

**Numerical gradients.** Finite float32 positions can have differences
that overflow a float32 subtraction (`1e38 - (-1e38)`), while a face
gradient assembled in wider precision may still be representable.
New helpers compute the differences and face cross-products in `double`,
then check every resulting `Vector3` gradient before committing any
of the three outputs. The existing per-node gradient sum, position
prevalidation, lambda and rigid-particle pinning logic remain intact.

This correction applies only while the existing volume mode is active.
The default volume-disabled path has no additional per-step allocations
or volume-gradient work. Face gradients cost extra double arithmetic in
opt-in mode; the performance impact must be measured.

## Test matrix

```bash
# Source/numerical reference checks:
python3 -m unittest discover -s tests/stress \
  -p test_physics_softbody_volume_safe.py -v

# Native tests in both float32 and double builds compiled with tests=yes:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[PhysicsVolume]"
```

Scene tests should cover a closed 1-mm tetrahedron, a 1-m tetrahedron,
large-world coordinates, pinned and fully pinned particles, invalid
winding, open cloth, XPBD area constraints and viscoplasticity. Compare
CPU time and RSS with volume disabled/enabled using the same timestep,
mesh and machine. **Native engine builds and real-world performance
measurements are not claimed by source tests.**

Related approaches: open-source PositionBasedDynamics XPBD volume
constraints, Jolt's 3D soft-body handling and the classic PBD closed-mesh
volume constraint.
