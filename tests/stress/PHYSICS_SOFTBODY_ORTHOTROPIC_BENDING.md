# Orthotropic cloth bending — XPBD dihedral hinges

## What this adds

Cgame already has an XPBD dihedral-angle bending solver, viscous
dihedral-rate damping and plastic rest-angle creep, plus orthotropic
stretch models under development. But all cloth hinges still have one
**isotropic** bending compliance: folding along woven warp and along
weft behaves identically.

This change introduces a CPU-native opt-in **orthotropic dihedral**
material factor, influenced by material-coordinate bending ideas used
in advanced textile models. It does not copy source from PhysX, Jolt,
Bullet or Blender and retains Cgame's existing XPBD solver.

Jolt release notes added soft-body dihedral constraints in v5.0;
the traditional PBD dihedral hinge is documented in Müller's 2007 paper.
We extend this existing hinge class with a direction-dependent
compliance factor instead of building a second bending solver.

## Project settings (GodotPhysics3D)

In ProjectSettings, before initializing the physics space:

    physics/3d/solver/soft_body_xpbd_dihedral_compliance = 0.00001
    physics/3d/solver/soft_body_xpbd_bend_weft_ratio = 5.0
    physics/3d/solver/soft_body_xpbd_bend_warp_axis = Vector3(1, 0, 0)

Defaults:

- \`soft_body_xpbd_bend_weft_ratio=1\`: **off**; exact historical
  isotropic behavior, no extra per-hinge buffers or calculation.
- \`soft_body_xpbd_bend_warp_axis=Vector3(1,0,0)\`: warp orientation in
  the original **mesh-local** coordinates, not world space.
- Ratio 5 means hinges oriented along the weft can bend 5 times more
  compliantly than hinges along the warp (not 5 times larger angles
  under every loading pattern). Ratio 0.25 makes weft folding stiffer.
- Ratios are clamped to [0.01, 100]. Invalid or zero warp axes
  fall back to the mesh-local +X direction.
- A positive \`soft_body_xpbd_dihedral_compliance\` is still required.

## Material law

For each *rest-mesh* hinge shared by two consistently wound triangles:

    e = normalize(rest_b - rest_a)     # edge is the fold axis
    n = normalize(normalize(n_face0) + normalize(n_face1))
    w = normalize(warp - dot(warp,n)*n)
    c2 = clamp(dot(e,w)^2, 0, 1)
    factor = c2 + weft_ratio*(1-c2)
    alpha_hinge = clamp(alpha_base*factor, 0, max(real_t))

If the two normals cancel because the undeformed hinge is folded
180 degrees, use the valid first-face normal. If an axis has
insufficient in-surface projection or the hinge is degenerate, use
factor 1 (normal isotropic bending) rather than generating NaN.

Here \`alpha_base=dihedral_compliance/dt^2\` is already used by XPBD,
and each hinge's factor is **computed once on mesh initialization**
from \`Node::s\` rest positions, so dynamically folding geometry
cannot change the material's warp/weft axes within a physics step.

XPBD Lagrange multipliers remain per hinge and are reset once per
simulation step, as before. No changes to signed dihedral gradients,
collision topology, pins, area/shear/stretch constraints or rendering.

## Cost and limitations

- No anisotropy: **zero new allocations or per-hinge processing**.
- Enabled: one \`LocalVector<real_t>\` factor per hinge — 4 bytes/hinge
  in 32-bit real_t, 8 bytes/hinge in double precision.
- Precomputation is O(hinges), once per topology/physics-space rebuild.
- In the solver, enabling orthotropy adds one multiplication and finite
  saturation per active hinge per iteration, but no extra hinge pass.
- Project-level material direction applies to all GodotPhysics3D
  soft bodies in one space. This is NOT per-vertex material painting,
  UV-based warp directions, a full anisotropic shell bending tensor,
  twist/Cosserat rods, FEM, fracture or anisotropic fluid drag.
- For curved/complex materials a single mesh-local vector may not
  represent a spatially varying fiber field. A future per-face UV
  director field would solve that problem.

## Validation

Python analytical + source contracts:

    python3 -m unittest discover -s tests/stress \
        -p test_physics_softbody_orthotropic_bending.py -v

Native C++ doctests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
        --test-case="[PhysicsOrthotropicBend]*"

14 native C++ cases: off/isotropic, warp/weft, diagonal smooth
interpolation, stiff weft, reversal of edge/axis, translation, mesh
scaling, rotation, projected direction, 180-degree fold fallback,
invalid geometry and parameters, and an actual pin-aware XPBD
dihedral comparison between stiff and compliant bending.

Before merging, test a pinned woven cloth with +X and +Y fold axes,
repeat at 60/120 Hz, with plastic creases and angular damping both
enabled. Bench 1k/10k/100k hinges for CPU p50/p95 and peak RSS.
Compare off vs on, verify material frame rotates properly when the
object is moved/rotated, and check no NaNs.

## Background

- Jolt soft-body dihedral introduction:
  https://jrouwe.github.io/JoltPhysicsDocs/5.1.0/md__docs__release_notes.html
- Müller et al., Position Based Dynamics (dihedral hinge):
  https://www.cs.cornell.edu/~utkarshm/cs775/pbd.pdf
- Blender XPBD compliance semantics:
  https://developer.blender.org/docs/features/nodes/xpbd_simulation/
