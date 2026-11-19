# GodotPhysics3D XPBD: numerical stability and scale

Cgame includes an **opt-in** XPBD distance-constraint solver for 3D soft
bodies. Configure `physics/3d/solver/soft_body_xpbd_compliance` to a positive
value (for example `0.00001`). The default `0` preserves the legacy PBD
solver; no changes to existing scenes are required. XPBD is a separate
backend from Jolt's native SoftBody simulation.

The XPBD distance constraint uses:

```text
C = |position_b - position_a| - rest_length
alpha_tilde = compliance / (physics_timestep^2)
delta_lambda = (-C - alpha_tilde * lambda) /
               (inverse_mass_a + inverse_mass_b + alpha_tilde)
lambda += delta_lambda
position_a -= inverse_mass_a * delta_lambda * direction
position_b += inverse_mass_b * delta_lambda * direction
```

Each link accumulates lambda during its solver iterations, then resets it at
the next physics step. Zero inverse mass pins a vertex. Positive compliance
allows gradual stretching; smaller values produce stiffer links. The existing
`linear_stiffness` factor scales compliance when XPBD is enabled.

## Extreme-scale hardening

- Position differences and squared distances use `double` intermediates,
  preventing finite 32-bit positions from producing a false overflow when
  calculating a squared link length.
- Tiny nonzero links are not rejected by the old fixed length epsilon.
- A correction that would overflow the stored lambda or particle positions
  leaves both positions and the multiplier unchanged.
- For tiny but finite time steps, the effective alpha saturates to the largest
  representable `real_t` instead of mistakenly selecting the rigid PBD path.
- Runtime memory is unchanged except for the existing optional XPBD link
  multipliers. The new kernel itself allocates no dynamic memory.

These changes improve the numerical kernel; **they do not implement XPBD
volume preservation, cloth self-collision, plasticity, tearing, or full FEM**.

## Verification

```bash
python3 -m unittest discover -s tests/stress \
  -p test_physics_xpbd_extreme_scale.py -v

# Using a native tests=yes build:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[PhysicsXPBD]"
```

Run both single-precision and `precision=double` builds, then compare
SoftBody3D cloth/rope stretch over different physics tick rates and solver
iteration counts. A source contract is not proof of a passing native build.
