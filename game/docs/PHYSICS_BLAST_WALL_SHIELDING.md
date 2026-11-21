# Cgame physics fields: wall shielding and velocity-change explosions

## Comparison with other engines

Unity's `Rigidbody.AddExplosionForce` applies an outward force with a
radius and upward modifier. Unreal Engine's radial impulses also expose
distance falloff and an optional **velocity change** mode, which scales
a body's physical impulse by its mass. Cgame's existing
`RadialForceField3D` already applies spherical impulses to
`RigidBody3D` and `PhysicalBone3D`, but did not distinguish between
fixed-momentum and mass-independent velocity changes and did not
account for walls absorbing a shockwave.

Cgame now adds both options directly to its native radial field.

## New engine properties

```gdscript
var field := RadialForceField3D.new()
field.radius = 10.0
field.strength = 12.0
field.falloff = RadialForceField3D.FALLOFF_QUADRATIC
field.collision_mask = 1 << 20 # What to push: debris.
field.mass_independent = true # Multiply impulse by the body's mass.
field.occlusion_mask = 1 # What blocks the shockwave: world geometry.
field.occlusion_attenuation = 0.25 # Transmit one quarter behind walls.
field.max_occlusion_rays = 24 # Hard per-activation synchronous query cap.
field.free_after_fire = true
add_child(field)
field.global_position = explosion_position
field.fire()
```

The engine's default remains `mass_independent=false` and
`occlusion_mask=0`, so unmodified projects preserve the original
behavior. The new properties also work with continuous radial fields
(strength is then interpreted as impulse/second), and negative strength
continues to pull bodies toward the field origin.

### Semantics

- **Targets**: the existing overlap query selects bodies and ragdoll
  bones on `collision_mask`, capped by `max_bodies`. Duplicate shape
  hits are deduplicated.
- **Range**: the same constant, linear, or quadratic falloff multiplies
  impulse magnitude; `falloff` is unchanged.
- **Velocity change**: if `mass_independent` is enabled, the applied
  physical momentum impulse is `strength × falloff × mass`. The
  resulting ideal instantaneous velocity change is independent of
  mass; collisions and constraints may affect final motion.
- **Wall shielding**: when `occlusion_mask != 0`, a ray is traced from
  the explosion origin to each affected body on the *separate* world
  obstacle mask. The recipient's RID is excluded from its own ray, and
  Area3D triggers cannot block it. If a ray hits an obstacle, the
  impulse is multiplied by `occlusion_attenuation` in [0,1].
- **Performance guard**: at most `max_occlusion_rays` (1–64)
  **additional** synchronous world collision queries per activation,
  irrespective of `max_bodies`. Remaining targets are conservatively
  attenuated, not accidentally exposed. If the source coincides with
  the recipient center, no extra ray is needed.
- **No async physics mutation**: `fire()` retains its existing
  off-physics-frame deferral, and the new checks occur within the
  existing physics thread query window. There are no new network
  messages or server authority changes.

This is collision-ray shielding, not a fluid blast simulation:
openings, diffraction, multi-path reverberation and destructible wall
failure are future extensions.

## Integrated into Albion After

`PhysicsDebris.blast()` now opts in via
`EngineFeatures.radial_push(..., BLAST_WALL_MASK,
BLAST_WALL_ATTENUATION, true, 2)`, selecting:

- Quadratic blast falloff, as used by the original debris fallback.
- Mass-independent velocity changes for lightweight wood, heavy debris
  and ragdoll bones.
- World-geometry occlusion on layer 1, transmitting 25% of impulse
  behind blockers. The debris and ragdoll collision layers are *not*
  used for shielding, preventing debris from screening other debris.
- At most 24 extra occlusion rays per explosion, while the existing
  `max_bodies` cap still applies.

`EngineFeatures` checks whether the running Cgame engine supports the
new setters. On upstream Godot or an older fork, it uses the
GDScript `PhysicsDebris._apply_blasts` path, which now implements the
same visibility rays, exclusion, conservative overflow rule and
mass-independent scaling, entirely inside `_physics_process`.

The change is strictly **client-side cosmetic physics**. Server
damage, hit detection, inventory and multiplayer synchronization do
not rely on this effect. A world must have colliders on
`BLAST_WALL_MASK` to shield anything; pure visual meshes are not
assumed to be obstacles.

## Validation

- Native C++ pure helpers, setter clamps and legacy defaults:
  `modules/gameplay_fx/tests/test_gameplay_fx.h`.
- Game parity/budget/feature negotiation tests:
  `game/tests/test_radial_blast_shielding.gd`.
- Real physics-world test with two different-mass rigid bodies and an
  intervening static wall:
  `game/tests/run_radial_blast_integration.gd`.
- Full game tests include the portable test; the dedicated CI job
  compiles Cgame, runs the native test, the portable game test and the
  real wall-occlusion test.

```sh
# With custom editor build:
godot --headless --test --test-case="*RadialForceField3D shielding*"
godot --headless --path game --script res://tests/run_radial_blast.gd
godot --headless --path game --script res://tests/run_radial_blast_integration.gd

# Stock Godot supports the pure fallback tests:
godot --headless --path game --script res://tests/run_radial_blast.gd
```

There are no measured performance or physics simulation claims until
the headless native integration tests and profiling complete.

## References

- [Unity Rigidbody.AddExplosionForce](https://docs.unity3d.com/ScriptReference/Rigidbody.AddExplosionForce.html)
- [Unreal Engine Apply Radial Impulse](https://dev.epicgames.com/documentation/en-us/unreal-engine/BlueprintAPI/Physics/AddRadialImpulse)
