# Cgame: optional radial elasticity for convex Jolt soft bodies

The prior convex-volume feature used one additional center particle and one
tetrahedral volume constraint per triangle. Preserving tetrahedron volume
**does not** independently determine the solid's elastic shape: substantial
shear/flattening can preserve volume.

This iteration builds on Jolt's existing XPBD edge solver to add
**center-to-surface radial rest-length constraints** for a validated closed,
convex soft mesh. This approximates volumetric shape retention; it is NOT
linear/corotated FEM and does not simulate real Young's modulus, Poisson ratio,
general anisotropic elasticity or plastic yield. Optional axis-weighted radial
compliance approximates a single preferred local material direction.

## Setup

Enable both options in Project Settings > Physics > Jolt Physics 3D > Simulation:

- `soft_body_volume_preservation = true` (default: false)
- `soft_body_volume_radial_springs = true` (default: false)
- `soft_body_volume_compliance = 0.00001` (default)
- `soft_body_volume_radial_compliance = 0.0001` (default)
- `soft_body_radial_anisotropy_axis = 0`: 0 isotropic (default), 1 local X,
  2 local Y, 3 local Z.
- `soft_body_radial_anisotropy_ratio = 1.0`: 0.1 to 10; values above 1
  soften radial deformation in the selected direction, below 1 stiffen it.

Lower compliance means stronger resistance to deformation. Both compliance
settings require finite nonnegative values and can be zero. Radial
compliance is additionally capped at 1.0 to prevent oversized
constraint denominators in the iterative solver.

When enabled on a valid convex closed mesh with V physics vertices and F
triangles, the feature adds V radial springs and F tetrahedral volume
constraints, plus a single interior particle. Existing surface constraints
and LRA constraints continue to work. When disabled, the new springs are
not built; when volume preservation is disabled, the optional fan is
skipped entirely.

Important: the interior fan particle and volume constraints are created
**before** LRA's closest-kinematic topology cache is populated. Otherwise
combining volume constraints with LRA can lead to an out-of-range cache read
inside Jolt's `Optimize()` routine. The volume fan must also precede the
surface-stiffness-to-XPBD mass conversion, which depends on particle count.
Every tetrahedral rest constraint is normalized to positive signed volume
because Jolt's solver uses signed volume gradients.

Radial springs are created **after** the surface shrink-factor adjustment,
with rest lengths based on the true center-to-surface distances. This avoids
inadvertently shrinking the solid interior while the outer cloth/skin rest
lengths are contracted.

Anisotropy is an angular blend:
`compliance = radial_compliance * [1 + (ratio - 1) * (delta_axis^2 / |delta|^2)]`.
It is tied to original mesh-local axes (not a rotating fabric fiber frame).
The factor is positive and bounded by `min(1, ratio)` and `max(1, ratio)`.
It is a lightweight directional shape-restoration control, NOT anisotropic FEM.

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
