# Cgame SoftBody3D thermal conduction and reversible expansion

## Motivation and comparison

GodotPhysics3D SoftBody3D in Cgame already supports XPBD stretch, non-linear
tension/compression hardening, irreversible damage, viscoplastic rest-length
change, shear/area/bending constraints, soft/soft contacts and volumetric FEM.
It has lacked a **thermal degree of freedom**: heating one part of a soft
mesh does not previously transmit heat or modify the elastic rest length.

Jolt/Bullet demonstrate advanced positional soft-body and deformable material
constraints; PBD continuum work shows how strain energy and geometry can be
coupled in a single solver. This PR introduces Cgame's **own small graph-based
thermomechanical material** rather than copying another engine's source.
It is not claiming to port a complete heat simulation from those engines.

## Material model

All stored node temperatures are in degrees Celsius, but only temperature
**differences** are used in constitutive equations. Absolute heat capacity
and thermodynamic units are not yet modeled.

**Conduction:** for every existing structural edge (a,b) once per tick,

    q = [1-exp(-2*k*dt)] / 2             # 0 <= q <= 0.5
    T_a' = T_a + q*(T_b - T_a)
    T_b' = T_b - q*(T_b - T_a)

The pairwise update solves equal-capacity two-node diffusion exactly,
conserves their heat sum and is unconditionally bounded for nonnegative
k and dt. Sequential links implement a graph Gauss-Seidel diffusion pass.
For complex meshes the result depends on link order and frame rate; this
is **not a mesh-independent Laplace-Beltrami thermal PDE discretization**.

**Ambient and heat source:** a temperature bath/thermostat, each with
rate r and constant target T_bath, is integrated as

    T_new = T_old + [1-exp(-r*dt)]*(T_bath - T_old).

The source only acts on nodes whose **predicted world-space position**
lies inside a fixed spherical region. When source rate=0 or radius=0
the source is absent. Ambient exchange is optional and may cool the mesh.
Pinned nodes conduct heat; pinning affects mobility, not heat capacity.

**Thermal expansion:** each XPBD edge uses

    T_edge = (T_a + T_b)/2
    scale = clamp(1 + alpha_T*(T_edge - T_ambient), 0.25, 4)
    L_elastic(T) = L_plastic * scale.

Only the **effective** XPBD rest length changes. The stored
\`Link::rl\` and \`Link::c1\` are **not** changed: a soft material can
heat, expand and cool back without the thermal feature inventing
irreversible creep. Genuine viscoplasticity can still change
\`Link::rl\` separately; the current plastic length is the new thermal
baseline.

Expanded rest length is frozen **once per physical step** after heat
conduction and after any plastic link creep; it is reused across all XPBD
iterations, and passed to:
- XPBD stretch/distance constraints.
- Nonlinear tension/compression stiffening and fatigue damage.
- XPBD strain limits (where enabled).

Other independent constraints (area, membrane, bending, volumetric
FEM, shape matching, tethers) keep their own undeformed geometry.
At high thermal expansion they can compete with thermal XPBD stretch;
tune material compliances for the intended interaction.

## Settings (ProjectSettings, GodotPhysics3D)

All settings are read once per physics space, consistent with the
existing Cgame settings model. Example:

    physics/3d/solver/soft_body_xpbd_compliance = 0.0001
    physics/3d/solver/soft_body_thermal_conduction_rate = 3.0
    physics/3d/solver/soft_body_thermal_ambient_exchange_rate = 0.15
    physics/3d/solver/soft_body_thermal_ambient_temperature = 20.0
    physics/3d/solver/soft_body_thermal_source_rate = 8.0
    physics/3d/solver/soft_body_thermal_source_temperature = 150.0
    physics/3d/solver/soft_body_thermal_source_center = Vector3(0, 1, 0)
    physics/3d/solver/soft_body_thermal_source_radius = 1.5
    physics/3d/solver/soft_body_thermal_expansion_coefficient = 0.001

Defaults and semantics:

| Setting suffix | Default | Meaning |
| --- | ---: | --- |
| conduction_rate | 0 | 1/s, graph-edge heat exchange |
| ambient_exchange_rate | 0 | 1/s, cooling/heating toward ambient |
| ambient_temperature | 20 | °C; initial and elastic reference |
| source_rate | 0 | 1/s, local thermostat rate |
| source_temperature | 100 | °C, may be heater or cooler |
| source_center | (0,0,0) | World-space center of sphere |
| source_radius | 0 | Meters, 0 disables source |
| expansion_coefficient | 0 | 1/°C, negative contraction on heating |

Conduction and ambient/source heat fields work without XPBD stretch,
but **thermal expansion requires nonzero XPBD compliance**. The
legacy soft body distance solver is unchanged.

All rates are sanitized to [0,1000] and temperatures to [-273,2000].
Source radius is sanitized to [0,10000]. Expansion coefficient is in
[-0.01,0.01]. Inputs with NaN/Inf are rejected or replaced by safe defaults.

## Cost

- At all-default settings: no thermal allocations or new O(nodes+links)
  passes. The method performs only a constant-time parameter check.
- With heat transport on: one \`LocalVector<real_t>\` temperature per
  node (4 bytes/node in float32, 8 bytes/node in double), updated once
  per physics tick in O(nodes + links).
- With thermal expansion and XPBD on: an additional 4/8 bytes/link for
  \`thermal_link_rest_lengths\`. Built ONCE per physics step and reused
  by all XPBD iterations.
- No allocations or dynamic data structures inside thermal helpers;
  buffers reset when the soft mesh is destroyed or when disabled.
- Flat-source membership uses double-precision world-space positions.

## Numerical and integration validation

Independent Python tests:

    python3 -m unittest discover -s tests/stress \
      -p test_physics_softbody_thermal_material.py -v

Native C++ doctests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
      --test-case="[PhysicsThermal]*"

19 C++ cases cover conservative heat exchange, many-node conduction,
large rates, time step splitting for a single edge and a bath,
temperature bounds, hot/cold/negative expansion, material reversibility,
the actual XPBD distance constraint, spherical sources, zero rates,
and invalid input atomicity.

18 Python tests cover independent heat oracles, link graph heat sum,
fixed node heat exchange, hot-spot propagation, source contracts,
project settings, XPBD solver wiring, fatigue/strain interactions,
default-path behavior and rest-length immutability.

**Required before merge:** create headless closed and open soft mesh
scenes with a hot sphere touching one side; verify measured temperature
profile, expanding/folding shape, cooling back, and interactions with
XPBD hardening, fatigue, fluid and soft-soft contacts. Benchmark 100,
1k, 10k, 100k links at 60/120 Hz: CPU median/p95, peak allocations,
temperature extrema, max XPBD residual and nonfinite counts.
Run full engine C++ build and all tests before merging.

## Limits and future work

This is a simple local thermal **graph transport** and thermal-expansion
material, not a full continuum thermodynamic FEM, phase-change solver,
thermal radiation, latent heat, combustion, anisotropic conductivity,
pressure-dependent heat transfer, true heat-capacity-weighted diffusion,
or friction-to-heat coupling. Source settings are global to a physics
space, not per-object GDScript properties; moving heat sources require
a future runtime API. No GPU temperature visualization is included.

Relevant reading:
- XPBD: https://matthias-research.github.io/pages/publications/XPBD.pdf
- Continuum PBD materials: https://www.sciencedirect.com/science/article/pii/S009784931400065X
- Cgame existing XPBD and thermal model source files.
