# SoftBody3D viscoelastic area-rate damping (GodotPhysics3D)

## Missing behavior and scope

Cgame already provides XPBD edge stretch, triangle area, nonlinear StVK
membrane strain and bending, plus longitudinal and dihedral velocity
damping. The triangle **dilatational velocity mode** (instantaneous rate
of surface area expansion/compression) previously lacked an independent
mass-weighted dashpot. This can leave rapid breathing/fluttering of soft
shells or cloth even when link and hinge damping is enabled.

Jolt soft bodies provide edge/dihedral/tetrahedral constraints. PhysX
deformable surfaces and volumetric FEM are broader alternatives. This
implementation adds a small CPU Kelvin-Voigt-style viscosity component
to our existing triangle system, *without importing external engine
code* and without requiring tetrahedral meshes or GPU FEM.

## Enable

Configure GodotPhysics3D Project Settings **before creation of the space**:

    physics/3d/solver/soft_body_area_rate_damping = 15.0

This is a dissipation **rate in 1/s**. Default **0** means disabled
with no additional face traversal. You can enable it independently of
\`soft_body_xpbd_area_compliance\`,
\`soft_body_xpbd_membrane_compliance\` or dihedral constraints.

To combine it with existing systems:

    physics/3d/solver/soft_body_xpbd_compliance = 0.0001
    physics/3d/solver/soft_body_xpbd_area_compliance = 0.00005
    physics/3d/solver/soft_body_area_rate_damping = 15.0
    physics/3d/solver/soft_body_link_damping = 2.0
    physics/3d/solver/soft_body_dihedral_damping = 1.0

The example values are starting points, not calibrated material
constants. Raising rate increases dissipation but also CPU work.

## Mechanics and proof sketch

For triangle vertices a, b, c:

    A = 0.5 * |(b-a) cross (c-a)|
    n = normalize((b-a) cross (c-a))
    g_a = 0.5 * (b-c) cross n
    g_b = 0.5 * (c-a) cross n
    g_c = 0.5 * n cross (b-a)

The area-change rate is \`r = sum(g_i dot v_i)\` and the inverse
effective mass is \`w = sum(inv_mass_i * dot(g_i,g_i))\`.

The rate controls the fraction of \`r\` removed each timestep:
    f = 1 - exp(-damping_rate * delta)
    impulse = -f * r / w
    new_v_i = old_v_i + inv_mass_i * g_i * impulse

Then \`r_new = (1-f) * r\` for the single-triangle update.
This relaxation is timestep-aware and bounded even for very high rates.
For a single impulse, the change in kinetic energy is
    ΔE = -f * (1 - f/2) * r² / w <= 0.

The area is invariant under rigid translations and rotations, so
\`sum(g_i) = 0\` and \`sum(x_i cross g_i) = 0\`. Consequently the
triangle impulse conserves **linear and angular momentum**, even with
different vertex masses. A pinned node with inverse mass zero receives
no velocity update.

We evaluate geometry, normals, gradients, rate, impulse and all three
candidate output vectors using double intermediates. On non-finite or
degenerate triangles the function fails **atomically**, without
changing any vertex velocity. No allocations or persistent buffers.

The extra O(faces) pass runs only when the setting is non-zero, and is
scheduled **before** the existing velocity-to-position reconstruction
in \`GodotSoftBody3D::solve_constraints\`, alongside the already present
longitudinal and dihedral damping. The main XPBD solver is unchanged.

## Limits

- **Surface area-rate viscosity only**. This is not a full nonlinear
  2D shear-viscosity tensor, volumetric poroelasticity, FEM viscous
  constitutive integration, self-healing material, fluid simulation,
  or stress-based fracture.
- The rate has a global per-space value, not per-material or per-face.
- Sequential per-face impulses on shared vertices are not equivalent
  to a globally implicit coupled viscosity solve. Individual impulses
  are energy dissipative, but global convergence still requires tests.
- It cannot change positions instantaneously; it acts on velocity
  prior to positional XPBD corrections.
- Geometrically degenerate faces and faces with all three vertices
  pinned are skipped. No effects on JoltPhysics3D or Physics2D.

## Validation

Numerical and source checks:

    python3 -m unittest discover -s tests/stress \
        -p test_physics_softbody_area_rate_damping.py -v

Native C++ doctests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
      --test-case="[PhysicsSoftAreaDamping]*"

13 native cases cover exact rate reduction, full relaxation, rigid
translation and rotation invariance, pinned particles, invalid
parameters, conservation of linear/angular momentum, energy
dissipation, face-winding and translation invariance, 1um triangles,
and atomic invalid/degenerate handling.

Before merging, exercise a waving cloth sheet and an inflatable
soft shell at 60 Hz and 120 Hz; measure p50/p95 physics-step CPU,
peak RSS, area-rate residual RMS and energy trends with 1k, 10k,
100k triangles. Verify no NaNs and compare default-off baseline
to enabled mode, including mixed XPBD area and membrane constraints.

## Background

- Jolt soft body: https://jrouwe.github.io/JoltPhysics/
- PhysX deformable surfaces: https://nvidia-omniverse.github.io/PhysX/physx/5.7.0/docs/DeformableBodyOverview.html
