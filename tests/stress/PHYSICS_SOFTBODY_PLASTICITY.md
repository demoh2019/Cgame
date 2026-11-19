# Cgame: viscoplastic deformation of 3D soft bodies

This opt-in extension to **GodotPhysics3D SoftBody3D** supports permanent
stretching and compression of the links connecting soft-body mesh particles.
It works with both the original PBD solver and the optional XPBD compliant
distance constraints. The implementation does not change the mesh topology.

## Settings

| Project setting | Default | Meaning |
| --- | --- | --- |
| `physics/3d/solver/soft_body_plastic_yield_strain` | `0.1` | Maximum elastic engineering strain (10%); 0–1 |
| `physics/3d/solver/soft_body_plastic_creep_rate` | `0` | Inverse-second creep rate; **zero disables plasticity** |

Example: `yield_strain=0.05`, `creep_rate=3.0`. While a mesh edge
stretches more than 5%, its reference length gradually increases. For
compression exceeding 5%, its reference length gradually shortens.

For an edge with length `L`, reference length `R`, strain limit `y`,
and time step `dt`, the target reference length is:

- stretched: `L/(1+y)` when `L>R*(1+y)`;
- compressed: `L/(1-y)` when `L<R*(1-y)` and `y<1`;
- otherwise no permanent change.

The exponential creep weight `f=1-exp(-rate*dt)` determines how quickly
`R` approaches the yield boundary. Computing it once per physics tick
avoids exp() calls inside the link loop. Both the legacy solver's squared
rest length and XPBD's linear rest length update consistently.

### Numerical and model limitations

- This is an **edge-based viscoplastic approximation**, not a full FEM
  constitutive law. It does not yet implement tearing, fractures, collision
  against itself, volume-preserving plasticity or stress-tensor hardening.
- Rest-length changes are measured from predicted particle positions before
  the elastic solver runs, so even stiff PBD links can yield under load.
- Pinned vertices remain pinned; plasticity changes link rest lengths only.
- The implementation avoids modifying non-finite lengths and skips changes
  that would overflow or underflow the legacy solver's squared rest length.
- ProjectSettings are sampled when a physics space is created. Existing spaces
  retain their cached settings until recreated.
- JoltPhysics3D is not affected; it has a different soft-body solver.

## Tests

```bash
python3 -m unittest discover -s tests/stress \
  -p test_physics_softbody_plasticity.py -v

# tests=yes binary, executable name varies by platform:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[PhysicsPlasticity]"
```

Run long-lived cloth/rope scenarios in both PBD and XPBD, including changes
to physics tick rate, paused/resumed simulation, pinned points and repeated
deformation. Measure time per soft-body solver step and RSS on the same
hardware; no improvement is claimed without runtime benchmarking.
