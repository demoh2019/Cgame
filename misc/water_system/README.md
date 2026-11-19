# Water System (experimental Godot 4.7+ addon)

First usable increment for **#8 Water System** in
[48-feature roadmap #61](https://github.com/demoh2019/Cgame/issues/61).
This is a lightweight surface simulation, not a production ocean, FFT
simulation, shallow-water solver or volumetric fluid.

## What works

- `WaterWave`: configurable wave direction, height amplitude, wavelength,
  angular speed and phase, with validation.
- `WaterProfile`: up to four travelling waves, deterministic height queries,
  analytic gradients and surface normals, reusable across scenes.
- `WaterSurface3D`: generated subdivided `PlaneMesh`, custom spatial shader
  and CPU/GPU synchronization of all wave parameters, time and visual settings.
- `WaterBuoyancy3D`: optional multi-point buoyancy and velocity drag for
  `RigidBody3D`. Sample points permit simple boats and floating crates.
- Headless tests for waves, surface shader uniforms, serialized profiles and
  buoyancy plus a demo scene under `demo/water_demo.tscn`.

The wave math on CPU and GPU is the same:

```text
phase = (2π / wavelength) × dot(normalized_direction, world_XZ)
        + phase_offset - angular_speed × time
height = amplitude × sin(phase)
normal = normalize((-dheight/dx, 1, -dheight/dz))
```

The shader renders displaced geometry while gameplay queries use the
same shared WaterProfile resource and simulation clock.

## Run the example

Open the `misc/water_system` folder as a Godot project and press Play.
The scene automatically creates three default waves and a water shader.

For another project, copy `misc/water_system/addons/water_system` to
`res://addons/water_system`. Add a `MeshInstance3D` and attach
`water_surface_3d.gd`, or select the registered `WaterSurface3D` script
class. The water surface automatically creates a wave profile and a
subdivided plane on entering the tree.

Customize `wave_profile` from Inspector: each `WaterWave` Resource has
`amplitude`, `wavelength`, `angular_speed`, `direction`, and `phase`.
The plane size and subdivision count are controlled by `surface_size` and
`subdivisions`; press **Build Water Surface** after editing mesh dimensions.

## Gameplay sampling

```gdscript
# The world position needs only its x and z components.
var sample := water_surface.sample_at(player.global_position)
if sample["ok"]:
    var water_level: float = sample["height"]
    var surface_normal: Vector3 = sample["normal"]

# Deterministic time overrides are possible for replay / tests.
var sample_at_ten_seconds := water_surface.sample_at(Vector3(1, 0, 2), 10.0)
```

Water height includes the WaterSurface3D node's world Y coordinate.
Samples outside the finite X/Z surface bounds return `ok=false`, so buoyancy
does not act across dry terrain.

## Buoyancy setup

Add a `WaterBuoyancy3D` as a direct child of a `RigidBody3D`. Set its
`water_surface_path` to the WaterSurface3D node using a NodePath (for
example, `../../Water` when the rigid body and water are siblings).
Use 1–8 local `sample_points` to approximate the underwater portion of a
boat, set `lift_per_meter`, `max_submergence` and `water_drag` relative to
the body's mass and gravity. Forces act at each sample point, allowing torque.

The component computes zero buoyancy for dry points, clamps submerged
depth, and adds drag opposing point velocity while underwater. It does not
replace Godot's rigidbody physics.

## Tests

Run with the same Godot editor binary as the demo:

```sh
godot --headless --path misc/water_system --editor --import --quit
godot --headless --path misc/water_system --script res://tests/test_water_system.gd
```

GitHub Actions downloads the official Godot 4.7.2 Linux binary, checks its
SHA-256 digest and runs the headless suite. It contains 16 groups and
90+ assertions on mathematical edge cases, default/invalid profiles, CPU
height and normals, time evolution, uniform packing, mesh parameters,
resource save/load and buoyancy.

## Limits and roadmap

- Maximum **four** waves. Surface is a finite plane, not infinite ocean or
  tiled clipmap.
- No Gerstner horizontal displacement, FFT, foam, shore intersection,
  refraction, caustics, reflections, underwater post-processing or
  volumetric fluids.
- CPU sampling and shader assume a **horizontal, unrotated WaterSurface3D
  with unit scale**. Do not rotate or scale the surface; resize the mesh.
- Visual geometry is subdivided at editor/import time and wave movement
  occurs in the vertex shader. Very large surfaces require additional
  tessellation, LOD and camera-relative origin techniques.
- Water surface does not automatically generate collision; buoyancy is
  implemented on rigid bodies separately. The drag model is approximate
  and should be tuned per gameplay object.
- This addon does not alter the engine's 3D renderer and is compatible with
  the other experimental Terrain, HLOD and WorldPartition PRs at file level,
  but integration with those components has **not yet been implemented**.

This PR is only a **first slice of item #8** in issue #61 and must remain
in Draft until headless CI and editor visual checks pass. It does not close
the full roadmap or imply all 48 feature areas are implemented.

Implementation and tests prepared with AI assistance; human review required.
