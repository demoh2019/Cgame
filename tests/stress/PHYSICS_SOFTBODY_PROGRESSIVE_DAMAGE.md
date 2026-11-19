# Progressive tensile damage for GodotPhysics3D SoftBody3D

## Physical motivation

Cgame already has compliant XPBD stretch constraints, tensile
hardening, viscoplastic changes of rest length and nonlinear surface
membranes. None of these retain the material's **loss of elastic
stiffness from a sustained tensile overload**.

This adds a bounded per-link internal damage variable, inspired by
continuum damage mechanics and the material history models used in
advanced deformable-body solvers. It uses our own small CPU XPBD law;
it is not copied from Jolt, Bullet or PhysX.

PhysX currently implements GPU-based FEM deformable surfaces and
volumes, with material properties including Young's modulus,
Poisson's ratio and elasticity damping. Bullet's soft-body material
defines link, area/angular and volume stiffness. Unlike those
uniform material settings, this proposal has **per-link irreversible
history** that influences compliance over later physics frames.

## Settings and activation

These are ProjectSettings read once at GodotPhysics3D space creation.
For example:

    physics/3d/solver/soft_body_xpbd_compliance = 0.0001
    physics/3d/solver/soft_body_xpbd_damage_rate = 5.0
    physics/3d/solver/soft_body_xpbd_damage_yield_strain = 0.15
    physics/3d/solver/soft_body_xpbd_damage_failure_strain = 0.55

- **damage_rate** (1/s, default **0**): 0 completely disables this
  feature and avoids per-link damage memory and history work.
- **damage_yield_strain** (default 0.15): threshold above which a
  link starts weakening. 0.15 means 15% engineering extension.
- **damage_failure_strain** (default 0.55): strain at which the
  damage *target* reaches its maximum; MUST be larger than yield.
  If invalid (<=yield), the feature is disabled.
- The max damage is hard-capped at 0.95. Links **stay connected**:
  maximum effective compliance is about 20x the original value.
  No graph edits, broken collision surfaces or retopology.

Setting \`soft_body_xpbd_compliance=0\` selects Godot's original PBD
distance solver, which is unaffected by the new damage settings.

## Constitutive model

For length L, rest length L0, yield y and failure f:

    e = max(0, L/L0 - 1)
    d_target = 0.95 * clamp((e - y) / (f - y), 0, 1)
    relax = 1 - exp(-damage_rate * dt)
    d_new = d_old + max(d_target - d_old, 0) * relax

No damage is added in compression or when unloaded. A link's damage
can never decrease, even if it later recovers its initial geometry.

The damaged XPBD compliance is

    alpha_damaged = alpha_material / (1 - d_new)

Thus damage gradually decreases material stiffness, with the response
remaining finite at the 0.95 cap. Damage is applied to the
existing tensile-hardening effective compliance if hardening is also
on; each link has **one frozen alpha per XPBD timestep**.

This is not a calibrated fatigue-cycle model, crack initiation
criterion, continuum viscodamage law or tensile plastic strain
integration. With strain held above yield for a sustained period,
damage approaches the target exponentially; the exponential form
gives timestep subdivision consistency at constant strain.

## Performance and memory

When off:
- **No per-link damage buffer** exists, no scan, and no added XPBD
  solver work beyond reading the once-cached settings.
- Existing \`xpbd_link_hardening_alphas\` is used only if tensile
  hardening itself was enabled, as before.

When on:
- An additional \`LocalVector<real_t> xpbd_link_damage\` consumes
  4 bytes/link in float32 builds, 8 bytes/link in double builds.
- Initializing this buffer occurs only when topology/buffer sizes
  change, not every step. It is reset when the SoftBody mesh
  deinitializes; this prevents stale history on topology rebuild.
- There is one O(links) scan to update damage and the existing
  per-step alpha buffer. The per-solver-iteration complexity is
  unchanged.
- No allocator calls in the per-link damage helper.

## Interoperability

- Works with global linear XPBD, tensile hardening, strain limits,
  bending and external fluid/wind forces.
- Existing viscoplastic changes of \`link.rl\` alter the definition of
  engineering strain. Use separate tests when both plasticity and
  progressive damage are enabled. Damage does not modify \`link.rl\`.
- Other independent area, StVK membrane, shape-matching or volume
  constraints can resist deformation even after edge weakening.
- Hard strain limits can override the damage-modified elastic
  response: choose material settings coherently.

## Verification and merge gate

Python analytical and source contracts:

    python3 -m unittest discover -s tests/stress \
        -p test_physics_softbody_progressive_damage.py -v

Native doctests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
        --test-case="[PhysicsSoftDamage]*"

13 C++ scenarios test compression, below yield, exponential response,
time-step subdivision, monotone history, unloading, partial overload,
saturation, geometry invariance, finite alpha, actual damaged XPBD
solver behavior, nonlinear tensile hardening composition and invalid
input atomicity.

Before merging: run a pinned curtain tensile pull-and-release test,
an inflated soft shell under repeated impacts, and a stress scene
with 1k/10k/100k XPBD links. Measure p50/p95 step CPU, max RSS,
residual stretch, max damage and NaN counts. Test both hardening and
viscoplastic creep enabled simultaneously; keep CI and native suite
green before merging.

## References

- PhysX deformable model:
  https://nvidia-omniverse.github.io/PhysX/physx/5.7.0/docs/DeformableBodyOverview.html
- Bullet soft-body materials:
  https://github.com/bulletphysics/bullet3/blob/master/src/BulletSoftBody/btSoftBody.h
- Jolt soft body constraints:
  https://jrouwe.github.io/JoltPhysics/
