# Nonlinear compressive buckling for GodotPhysics3D SoftBody3D

## Why this exists

Cgame now has XPBD stretch, triangle-area/shear, dihedral bending,
tension-hardening, viscoplastic creep and global corotational shape
matching. But a *thin membrane is very different in extension and
compression*: it carries considerable tension, then folds/wrinkles
under compression.

PhysX deformable FEM bodies represent more detailed volume/surface
elasticity but require a compatible GPU. Jolt supports compliant
edge and dihedral constraints. We can approximate the
tension/compression material asymmetry cheaply inside our existing
CPU XPBD stretch solver, without importing another engine.

References:
- PhysX Deformable Body Overview:
  https://nvidia-omniverse.github.io/PhysX/physx/5.7.0/docs/DeformableBodyOverview.html
- Jolt SoftBody Shared Settings:
  https://jrouwe.github.io/JoltPhysicsDocs/5.7.0/class_soft_body_shared_settings.html

## Project settings

All values are global for a GodotPhysics3D physics space; set them
before physics-space creation (or restart the scene):

    physics/3d/solver/soft_body_xpbd_compliance = 0.0001
    physics/3d/solver/soft_body_xpbd_buckling_softening_ratio = 9.0
    physics/3d/solver/soft_body_xpbd_buckling_yield_strain = 0.05
    physics/3d/solver/soft_body_xpbd_buckling_transition_strain = 0.1

Defaults are ratio = 1.0 (off), yield = 0.05 and transition = 0.05.
The feature requires positive base XPBD compliance; it never modifies
the historical PBD fallback. The ratio must be >= 1, with 1 retaining
exact legacy XPBD behavior. A ratio of 9 means a fully compressed
link is **9x more compliant** than a link in tension.

## Constitutive law

We use the positive compression measure c = max(0, 1 - L / L0),
where L0 is the (possibly plastically evolved) link rest length.

For compression yield y, transition width w, and compliance ratio r:
    t = clamp((c - y) / w, 0, 1)
    s = t*t*(3 - 2*t)
    alpha_eff = alpha_base * (1 + (r - 1)*s)

A zero transition width switches immediately after yield.
At the yield itself and for tensile links, alpha_eff = alpha_base.
We use double intermediates, saturate to maximum finite real_t and
reject nonfinite/negative parameters.

The link compliance is calculated ONCE per physics step (not inside
XPBD iterations), so the existing link Lagrange multiplier is always
paired with one fixed alpha. This matters for solver convergence.
When tension hardening is enabled too, we apply tensile and compressive
laws consecutively to the same per-link alpha. The two regimes are
mutually exclusive because tension and compression strains cannot both
be positive on the same link in the same step.

The new feature reuses the existing
\`xpbd_link_hardening_alphas\` scratch array for both models,
allocating **one** scalar per link when nonlinear links are active,
and **zero** new scratch memory in the default-off mode. The
existing per-link alpha buffer is released when neither model is
enabled. Time complexity O(links), once per timestep.

## What it does not do

- This is **not** a full Euler shell buckling eigenproblem, FEM
  elasticity, Cosserat rod solver, stress-based fracture, or GPU cloth.
- It modulates XPBD edge stiffness in compression; it does not inject
  an out-of-plane wrinkle or pick a specific wrinkle wavelength.
  Wrinkling geometry requires sufficient mesh resolution and
  appropriate bending/area constraints.
- In highly constrained systems, existing independent strain clamps,
  area preservation or shape matching may dominate compression and
  prevent visible folds. Tuning multiple constraints is necessary.
- ProjectSettings are per-space, not per-mesh materials.
- No effect on JoltPhysics3D, 2D physics, or the legacy PBD link solver.
- Extreme stiffness ratios can lower nonlinear solver convergence.
  Use fixed timesteps and enough iterations, and benchmark by scene.

## Verification and CI

Python numeric/source contracts:

    python3 -m unittest discover -s tests/stress \
        -p test_physics_xpbd_compression_buckling.py -v

Native Doctest tests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
        --test-case="[PhysicsXPBDBuckling]*"

Test scenarios include actual XPBD compressive restoring-force comparison,
tension/buckling composition, disabled mode, tension invariance, yield,
smoothstep midpoint, saturated compression, discontinuous transition,
fully collapsed link, zero rest length, translation/reversed links,
yield at 100%, floating-point saturation and invalid input with
preserved output.

Before merge, validate three headless scenes:
1. Hanging pinned curtain with dihedral bending and shear constraints
   (fold under lateral compression, no excessive lengthening).
2. Soft spherical shell compressed against a static obstacle, then
   released (shape recovery without NaNs).
3. Elastic soft body with both tension hardening and buckling on.
   Compare with hardening-only and buckling-only to detect interference.

Measure physics-step p50/p95 CPU, peak RSS, solver iterations and
constraint residuals at 1k/10k/100k links on the same fixed machine.
Keep PR draft until native build and scene tests pass.
