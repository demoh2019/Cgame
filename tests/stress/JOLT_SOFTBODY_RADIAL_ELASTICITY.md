# Cgame: optional radial elasticity for convex Jolt soft bodies

The prior convex-volume feature used one additional center particle and one
tetrahedral volume constraint per triangle. Preserving tetrahedron volume
**does not** independently determine the solid's elastic shape: substantial
shear/flattening can preserve volume.

This iteration builds on Jolt's existing XPBD edge solver to add
**center-to-surface radial rest-length constraints** for a validated closed,
convex soft mesh. This approximates volumetric shape retention; it is NOT
linear/corotated FEM and does not simulate real Young's modulus, Poisson ratio,
anisotropy or plastic yield.

## Setup

Enable both options in Project Settings > Physics > Jolt Physics 3D > Simulation:

- `soft_body_volume_preservation = true` (default: false)
- `soft_body_volume_radial_springs = true` (default: false)
- `soft_body_volume_compliance = 0.00001` (default)
- `soft_body_volume_radial_compliance = 0.0001` (default)

Lower compliance means stronger resistance to deformation. Both compliance
settings are clamped to finite nonnegative values, and can be zero.

When enabled on a valid convex closed mesh with V physics vertices and F
triangles, the feature adds V radial springs and F tetrahedral volume
constraints, plus a single interior particle. Existing surface constraints
and LRA constraints continue to work. When disabled, the new springs are
not built; when volume preservation is disabled, the optional fan is
skipped entirely.

Important: radial springs are created **after** the surface shrink-factor
adjustment, with rest lengths based on the true center-to-surface distances.
This avoids inadvertently shrinking the solid interior while the outer
cloth/skin rest lengths are contracted.

The volume fan's validity constraints remain unchanged: at most 2048
vertices and 4096 triangles, finite input positions, closed 2-manifold
with consistent winding, and convex surface geometry. Runtime pin/unpin
does not reconstruct the constraints; recreate the soft body to change
the constraint topology.

## Validation

Source and mathematical contracts:

    python3 -m unittest tests/stress/test_jolt_softbody_radial.py -v

Native Cgame Jolt editor regression:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
        --path tests/stress/jolt_radial \
        --script res://radial_elasticity_regression.gd

The native scene simulates a pinned cube under impulse/gravity, checks
bounds and all surface vertices for finite coordinates and verifies fixed
anchors. It does not directly measure material stress or benchmark CPU
cost against the previous implementation.

Performance: extra Jolt edge constraints are O(V), expected to increase
solver work and RAM while enabled. Measure frame time, initialization
time and peak RSS on 16, 256 and 2048 vertex convex meshes. Never claim
speedups without measured baselines.
