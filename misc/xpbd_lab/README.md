# Cgame XPBD Physics Lab — ropes and cloth

This folder adds an **opt-in** pure-GDScript, CPU extended position-based
dynamics (XPBD) prototype to the Cgame/Godot fork. It adds new controllable
behaviour **alongside** Godot and Jolt soft bodies. It does not replace the
existing physics servers or claim better performance than native Jolt.

## Implemented

- Distance constraints with rest length, compliance in m/N and XPBD accumulated
  Lagrange multiplier, reset once **per substep**.
- Rope chains with structural links and second-neighbor bending links.
- Cloth grids with stretch (horizontal/vertical), shear (diagonal) and bending
  (second-neighbor) constraints.
- Two pinned cloth corners by default, configurable rope endpoint pinning, and
  dynamic pin repositioning for kinematic anchors.
- Optional strain-triggered tearing of individual constraints (visualized as
  detached lines).
- Explicit timestep subdivision, damping and wind-relative acceleration.
- **One-way** collisions against a static horizontal floor and configurable
  static spheres. Per-contact tangential damping approximates friction.
- Headless regression suite for compliance, residual, pinning, topology,
  tearing, collisions, wind, determinism, and invalid inputs.
- An interactive rope/cloth scene with a manual stress/tear control.

Physics formulas are derived from the XPBD formulation (Macklin et al., 2016):
`DeltaLambda = (-C - alpha * lambda) / (sum(w * |gradC|^2) + alpha)`,
with `alpha = compliance / (substep_time^2)`.

## Run

Open `misc/xpbd_lab/project.godot` in Godot 4.6+ or run

```sh
godot --path misc/xpbd_lab
```

- `W` toggles wind.
- `T` applies an instantaneous stretch to tear selected links.
- `R` rebuilds the rope and cloth.

Copy `misc/xpbd_lab/addons/cgame_xpbd` into an existing Godot project under
`res://addons/cgame_xpbd` to reuse it.

## Tests

```sh
godot --headless --path misc/xpbd_lab --import
godot --headless --path misc/xpbd_lab --script res://tests/test_xpbd.gd
```

The test exits nonzero on an assertion failure. A GitHub Actions workflow
runs this independent project against a stable Godot release. A passing
headless script does not guarantee the **fork's C++ editor build** passes.

## Known limitations and correctness boundaries

- This is **point-mass cloth and rope**, not volumetric FEM or full material
  plasticity, strain-rate constitutive modelling or mesh pressure.
- Rendering uses line segments for intact stretch constraints; no skinned
  triangle mesh/texture generation, shadows, surface normals, or thickness.
- Plane and sphere collisions are user-defined and **one-way**. There is
  currently no runtime coupling back to `RigidBody3D`, no arbitrary mesh/scene
  collision and no continuous swept collision detection.
- No particle-particle, cloth-cloth or strand self-collision; no knots,
  frictional contact patch or volume conservation.
- Torn constraints remain in the array marked inactive (no topology remesh).
  Isolated points still simulate; cloth triangles are not reconstructed.
- Wind is a velocity-relaxation approximation, not aerodynamic pressure on
  triangle normals or fluid coupling.
- Time steps above 1/15 second are clamped to protect against hitches, so
  simulation time advances slower than wall time in long frames.
- Direct dictionary constraints and single-threaded CPU per-particle update
  are intended for small demos. Batch arrays, spatial hashing, parallelism
  and independent stress/performance benchmarks are future tasks.
- Pinning only supports an inverse-mass-zero point; there is no unpin API.
  Changes to the parent transform during simulation are not modeled as
  fictitious acceleration. Keep its transform constant in the prototype.

Follow-up milestones: actual triangulated cloth surface, spatial hash
self-collision, tearing of face topology, broadphase scene collision,
rigid-body feedback, performance benchmarks and precision/stability checks.

## Technical references

- Macklin, Müller, Chentanez (2016): XPBD position-based compliant constraints.
  https://doi.org/10.1145/2994258.2994272
- Bullet soft-body rope and cloth demo architecture:
  https://github.com/bulletphysics/bullet3
- Jolt soft-body system and its current constraints:
  https://jrouwe.github.io/JoltPhysics/
- NVIDIA PhysX PBD particles:
  https://nvidia-omniverse.github.io/PhysX/physx/5.1.1/docs/ParticleSystem.html

No third-party library source code is copied into this implementation.
