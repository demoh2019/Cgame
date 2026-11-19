# Orthotropic XPBD cloth stretch in GodotPhysics3D

## Motivation and physics-engine comparison

Cgame already supports isotropic XPBD stretch, triangle area/shear
constraints, bending, viscoplasticity, strain limits, enclosed volume,
adiabatic-gas pressure and various CCD methods. A missing material feature
is **directional stretch compliance**: real woven fabric usually has
different extension along its warp fibers and across those fibers.

NVIDIA PhysX classifies cloth constraints into independent horizontal,
vertical, shearing and bending phases with separate stiffness values.
PositionBasedDynamics provides orthotropic cloth models with different
XX, YY and XY stiffness. Cgame can offer an efficient first step without
changing its existing topology or adding a second cloth solver.

References:
- PhysX cloth constraint phases:
  https://nvidiagameworks.github.io/PhysX/3.4/PhysXGuide/Manual/Cloth.html
- PositionBasedDynamics cloth options:
  https://positionbaseddynamics.readthedocs.io/en/latest/file_format.html

**Scope:** directional XPBD *distance-link compliance* in mesh-rest
coordinates. It is **not** a full continuum orthotropic FEM constitutive
model, UV-mapped per-triangle material basis or Poisson-coupled material.

## Configuration

With the GodotPhysics3D backend and XPBD stretch enabled:

```ini
[physics]
3d/physics_engine="GodotPhysics3D"
3d/solver/soft_body_xpbd_compliance=0.0001
3d/solver/soft_body_fiber_axis=Vector3(1, 0, 0)
3d/solver/soft_body_fiber_compliance_ratio=0.25
```

The **default** ratio is `1.0` (isotropic, exactly the prior XPBD
solver), with default fiber axis `(1,0,0)`.

- Ratio `0.25`: fibers aligned with the axis have one quarter of
  normal XPBD compliance — approximately four times stronger against
  stretch than perpendicular links at the same timestep.
- Ratio `1.0`: isotropic behavior unchanged.
- Ratio `4.0`: aligned fibers are four times more compliant (softer).
- Ratio `0.0`: idealized inextensible fiber direction in this XPBD
  distance constraint (subject to other constraints/solver iteration
  accuracy).
- Edge directions halfway between fiber and cross-fiber interpolate
  smoothly by squared directional cosine, avoiding abrupt stiffness
  discontinuities.

The fiber axis is defined in the **original rest-mesh coordinate
frame**, rather than in world space each step. Rigid rotation of a
deforming body does not change which links represent warp/weft.
Reverse edge order or reverse the fiber vector: same material result.
It is a global constant basis for each physics space, not a UV-based
locally varying weave direction. A nonfinite or zero axis falls back to
(1,0,0); the ratio is clamped to [0,100].

Settings are read and sanitized **once per GodotSpace3D**. Recreate the
space to pick up changes in ProjectSettings.

## Model and implementation

For a rest edge `e = rest_b - rest_a` and a fiber unit axis `f`:

```text
cos²(theta) = clamp((dot(e,f)²)/(dot(e,e) dot(f,f)), 0, 1)
compliance_multiplier = 1 + (fiber_ratio - 1) cos²(theta)
link_alpha = isotropic_alpha * compliance_multiplier
isotropic_alpha = configured_compliance / (stiffness * dt²)
```

The new `servers/physics_xpbd_cloth_fiber.h` calculates this with
double intermediates, early guards for invalid/degenerate geometry and
finite saturation for both `real_t=float` and `real_t=double`. No
mutation occurs on failure, so an invalid rest edge falls back to
isotropic compliance. Pinned vertices still have zero inverse mass in
the unchanged XPBD distance solver.

Cgame already has a once-per-step `xpbd_link_hardening_alphas` vector
that freezes nonlinear tension-hardening compliance for all XPBD
iterations. The anisotropic mode **reuses that exact same optional
scratch vector**, independent of whether tension hardening is enabled:

1. Read the cached fiber ratio and axis once per solve step.
2. When XPBD is active and ratio != 1, for each link compute the
   directional multiplier from the **rest** edge and apply it to the
   existing (possibly tension-hardened) `link_alpha`.
3. Freeze the final alpha for all solver iterations while XPBD
   Lagrange multipliers accumulate. This avoids inconsistent lambda
   updates and a second per-link array.
4. With ratio 1 and tension hardening OFF, skip the entire new O(E)
   prepass, retain `alpha` directly and free the optional scratch
   as the original solver already does. Legacy non-XPBD PBD remains
   unchanged.

### CPU/RAM tradeoffs

When enabled, there is one additional rest-edge pass per step and one
cached `real_t` alpha per link, **already shared** with tension
hardening if that feature is used. No dot products, axis normalization,
per-link material calculations or setting lookups take place inside
the inner XPBD iteration loop. No additional spatial index or per-face
array is constructed. **This is a material-quality feature, not a
speedup**; enabled performance must be measured under actual load.

When disabled (ratio=1), no extra scratch is allocated, no new per-link
pass runs, and the previously existing alpha selection is unchanged.

## Verification

```sh
# Source contracts:
python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_cloth_fiber.py' -v

# Compile the actual header with minimal test-only Vector3 (not engine):
g++ -std=c++17 -O2 -Wall -Wextra -Werror -pedantic \
  -Itests/stress/mock_xpbd_cloth_fiber -I. \
  tests/stress/physics_xpbd_cloth_fiber_standalone.cpp -o /tmp/cgame-fiber
/tmp/cgame-fiber

# Native tests require a Cgame editor built with tests=yes:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Orthotropic cloth warp and weft compliances follow rest fibers"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Orthotropic cloth axis reversal and rigid rest translations are invariant"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Orthotropic cloth handles zero and isotropic ratios"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Orthotropic cloth rejects degenerate and nonfinite input without mutation"
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[Physics] Orthotropic cloth XPBD stretch actually resists warp more than weft"
```

The native suite also runs the actual `physics_xpbd_solve_distance`
constraint on identically stretched pinned warp/weft links, asserting
less residual stretch along the stiffer warp orientation. This
integration regression is not exercised by the standalone mock.

The independent `physics-xpbd-cloth-fiber.yml` workflow compiles
actual Cgame math with GCC/Clang on **float and double**, and compares
**25,000 deterministic randomized material directions** per matrix
job against a separately calculated double-precision formula.

Before merging to `develop`, run the full native build, C++ tests,
a hanging cloth drape with the fiber axis aligned and rotated, verify
different warp/weft extension and pin invariance, compare cloth scene
p50/p95/p99 physics-step time and peak RAM, and check that ratios 1.0
match unchanged XPBD simulations exactly. Ensure no conflict with
existing tension-hardening, strain limits and shear constraints.
