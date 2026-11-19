# ConvexPolygonShape3D aerodynamic polygon facets — Cgame

## Goal and physics-engine comparison

Cgame GodotPhysics3D supports Jolt-inspired point forces, rigid-body
fluid drag, exact convex submerged-volume buoyancy, and separate soft-body
aerodynamics. A separate open PR #703 introduces six-panel drag for
**BoxShape3D**. The missing generalization is **actual convex hull
polygon panels** on RigidBody3D: they may be tetrahedral, wedge shaped,
sculpted or other low-poly convex solids with arbitrary face normals
and significant aerodynamic torque.

This PR implements an independent **facet pressure and tangential shear**
model for ConvexPolygonShape3D. It uses the existing
\`Geometry3D::MeshData\` created by Godot's convex hull code, not AABBs
or pre-generated mesh assets. Jolt's force-at-position approach provides
the reference integration pattern; the aerodynamic law and kernel are
new Cgame code, not taken from Jolt, Bullet or PhysX.

Read:
- https://jrouwe.github.io/JoltPhysics/class_body_interface.html
- https://docs.godotengine.org/en/stable/classes/class_physicsserver3d.html

## Geometry: true polygon center of pressure

For each hull's face with \`n\` vertices, triangulate in-order as a fan
\`(p0,p1,p2), (p0,p2,p3), ...\`. Sample area and area-weighted centroid:

    A_i = 0.5 * |(p_i - p0) × (p_(i+1) - p0)|
    C_i = (p0 + p_i + p_(i+1))/3
    A_f = sum(A_i)
    C_f = sum(A_i*C_i) / A_f

Face unit normal is the direction of the total signed cross-product
sum, flipped so it points **away from the convex hull's vertex mean**.
For a nondegenerate closed convex hull, that vertex mean is interior
and safely resolves flipped winding and negative-determinant affine
world transforms. This works with mirrored, sheared and nonuniformly
scaled hulls. Invalid faces or indices reject the entire shape step
transactionally, rather than applying a partially valid force.

The total area and center of pressure are invariant to whether a
quad face is represented as a triangle fan internally. **One polygon
is one panel**, so the model avoids a spurious mesh-density dependency
caused by each triangle independently reacting to changing velocity.

## Force and torque

For each polygon's world center \`C_f\`, normal \`n\`, true area \`A_f\`:

    lever = C_f - body_world_COM
    u = v + omega × lever - wind_velocity
    u_normal = dot(u,n)
    u_tangent = u - u_normal*n

    F_pressure = -0.5*rho*Cp*A_f*max(u_normal,0)^2*n
    F_skin = -0.5*rho*Cs*A_f*length(u_tangent)*u_tangent
    F_total = F_pressure + F_skin

The normal term is **windward-only pressure drag**, not a full
bi-directional pressure distribution. Tangential quadratic resistance
damps translation and can damp rotation. The ideal instantaneous
force is dissipative relative to the flow at the panel center
(\`F·u <= 0\`) and does not act when the local body surface is
stationary relative to the medium.

Each panel applies an inertial point impulse, including the torque

    dir = F/|F|
    r = lever × dir
    k = inverse_mass + dot(r, inverse_inertia_world*r)
    J = min(|F|*dt, max(0,-dot(u,dir))/k)

    v' = v + inverse_mass*dir*J
    omega' = omega + inverse_inertia_world*(lever × (dir*J))

\`k\` is the directional inverse effective mass. The cap prevents one
face's impulse from **reversing the local resisting velocity along
the applied direction** at very large time steps and bounds energy
change for a physically valid inertia tensor. Temporary velocity
updates follow hull polygon order (Gauss-Seidel), and both velocities
are committed **only after all polygons succeeded**.

A convex hull with >512 vertices or >256 faces is rejected before
iteration. Polygon processing uses stack scalars and a 3-vector
result; no per-body/face dynamic allocations or extra collision
queries in the helper. Complexity O(vertices + polygon indices).

## ProjectSettings

Both force coefficients default to **zero**, so legacy Godot physics
remains unchanged. Set before creating the physics space:

    physics/3d/solver/rigid_convex_aero_pressure_coefficient = 1.0
    physics/3d/solver/rigid_convex_aero_skin_coefficient = 0.05
    physics/3d/solver/rigid_convex_aero_density = 1.225
    physics/3d/solver/rigid_convex_aero_wind_velocity = Vector3(5,0,0)

All settings are global per GodotPhysics3D space, validated/cached at
construction. Coefficients: [0,10]. Density: [0,2000] kg/m³.
World wind vector: finite coordinates only, otherwise zero.
At zero density or with both coefficients at zero, the extra loop
does not run. No allocations in the disabled path.

### Godot engine integration

Inside \`GodotBody3D::integrate_forces()\`:
- Applies only to a dynamic **RigidBody3D** running built-in force
  integration, never static/kinematic.
- Iterates enabled collision shapes and processes
  **SHAPE_CONVEX_POLYGON only**; boxes belong to their own optional
  panel model (open PR #703).
- Uses the complete body × local-shape affine transform, cached
  \`_inv_mass\`, world \`_inv_inertia_tensor\`, actual body COM and
  angular velocity.
- After external forces / gravity, fluid buoyancy and quadratic
  drag / gyroscopic integration, before the engine's existing
  angular/linear speed caps and CCD sweep.
- Existing \`fluid_linear_drag\` and \`fluid_plane\` options can
  compound aerodynamic effects. Disable them in wind benchmarks
  unless double-counting is intended.

## Worked example

An unrotated convex cube with half-extents (1,1,1), v=(10,0,0)m/s,
rho=1, Cp=1, Cs=0, mass=1kg, dt=0.01s:

- Only the +X polygon receives normal pressure.
- True exposed area is 4m².
- F_x=-0.5×1×1×4×10²=-200N.
- The new velocity after one tick is **(8,0,0)m/s**.
- A nonuniform transform with world half-extents (2,3,4), dt=0.001,
  exposes 48m² and gives **(7.6,0,0)m/s**.

A world-space hull offset from COM gets \`lever × impulse\` torque.
For an offset in +Y and v in +X, aerodynamic drag in -X
induces positive Z angular velocity.

## Test plan

Independent Python source contracts and physics oracles:

    python3 -m unittest discover -s tests/stress \
      -p test_physics_rigid_convex_aero_facets_3d.py -v

Godot native C++ doctests:

    scons platform=linuxbsd target=editor dev_build=yes tests=yes -j4
    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
      --test-case="[PhysicsConvexAero]*"

21 C++ cases cover polygon area/center/normals, reversed winding,
nonuniform scale and reflections, default-off, windward pressure
analytical reference, density, coarse time steps, Galilean invariance,
offset moment, spin drag, long-term energy dissipation, genuine
tetrahedral hulls, invalid late-face rollback, degenerate faces,
over-budget hulls, negative/NaN inputs, exact affine stretch and
world translation invariance.

20 Python tests provide independent facet integration mathematics,
energy oracle (30 steps), and source/ProjectSettings wiring checks.

### Before merge

- [ ] Native engine C++ build and 21 doctests pass, float32 and double.
- [ ] GitHub Actions Python analytical/source suite green.
- [ ] Headless scenes: convex tetra/wedge/ship hull/compound COM offset,
      stationary and moving wind, rotating mirrors/shear, 60/120/240Hz.
- [ ] Wind/turbulence trajectory benchmark and contact/CCD interactions,
      with no NaN/Inf and controlled kinetic-energy behavior.
- [ ] Compare 100, 1k, 10k, 100k convex meshes: p50/p95 physics step,
      peak memory, off-path overhead and allocation counts.
- [ ] Confirm coexistence/rebase with open PR #703 box aerodynamics,
      and update once \`develop\` advances.

## Limitations and future work

This is a low-cost **pressure/shear panel drag approximation**, not
Navier-Stokes CFD, vortex wake, turbulence, wind shadowing, physically
calibrated wing lift or dynamic two-way gas/rigid interaction.
Panel-center quadrature approximates how pressure varies over large
faces. No per-material/per-body coefficients or runtime wind change
are exposed yet; ProjectSettings apply across the whole space.
Fluid and aerodynamic options may stack.

Next extensions: oriented lifting panels with calibrated lift/drag
polars and stall; center-of-pressure shifts; occlusion and wake;
actual deformable aerodynamic surface material; runtime per-body
aerodynamic coefficients; and per-space moving wind fields.
