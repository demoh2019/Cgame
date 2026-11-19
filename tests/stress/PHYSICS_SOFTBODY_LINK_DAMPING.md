# Cgame SoftBody3D: relative link velocity damping

The GodotPhysics3D soft-body backend now has an **opt-in link-aligned
viscous dashpot**. It supplements existing global damping, PBD and XPBD
distance/area/dihedral/volume/tether constraints and viscoplastic yielding.

## Configuration

Set `physics/3d/solver/soft_body_link_damping` in Project Settings.

| Value | Behavior |
| ---: | --- |
| `0` (default) | Disabled; no extra O(links) pass and no solver behavior change |
| `1` | Rate 1/s; roughly 63% longitudinal velocity relaxation per second |
| `5` | Strong oscillation damping; ~99% relaxation per second |
| `100+` | Very strong damping; may make cloth/rope feel overdamped |

The setting is read when a physics space is created; recreate the space
after changing it. It applies to soft-body links including generated
distance-based bending links. It does not add permanent per-link memory.

## Numerical model

Each link joining particles A and B forms a mass-weighted dashpot:

```text
n       = normalize(position_B - position_A)
v_rel   = dot(velocity_B - velocity_A, n)
fraction = 1 - exp(-rate * physics_delta)
J       = -fraction * v_rel / (inverse_mass_A + inverse_mass_B)
velocity_A -= inverse_mass_A * J * n
velocity_B += inverse_mass_B * J * n
```

The damping pass occurs after force/gravity prediction, before position
projection. It only suppresses **relative longitudinal** motion.
Transverse motions, bulk translation and rigid rotation are preserved.
The two impulses are equal/opposite and parallel to the link, conserving
linear and angular momentum for the isolated pair. Pinned particles have
inverse mass zero and remain fixed. Exponential integration avoids strong
time-step sensitivity for a link with constant direction.

This is link-relative viscous damping, **not** a full continuum FEM
Kelvin-Voigt constitutive model, not collision damping, and not
soft-body self-collision.

## Verification

```bash
python3 -m unittest discover -s tests/stress -p test_physics_softbody_link_damping.py -v
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="[PhysicsLinkDamping]"
```

Run scenes with a hanging cloth, a pinned rope and a closed soft volume at
various physics ticks. Compare relative stretch oscillation, step p95,
conserved center-of-mass velocity, and process RSS with a baseline run.

The isolated numerical contracts and source checks are not a replacement
for a compiled, real-engine test. No measured speedup is claimed.
