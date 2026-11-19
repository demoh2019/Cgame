# SoftBody3D: optional XPBD vertex/face self-contact friction

Cgame's built-in GodotPhysics3D now offers a separate dimensionless
**tangential friction coefficient** for XPBD self-contacts. This extends
the existing optional vertex/face collision thickness and compliance;
it does not replace the normal contact solver.

## Settings

| Project setting | Default | Purpose |
| --- | ---: | --- |
| `physics/3d/solver/soft_body_self_collision_thickness` | 0 | Enable discrete vertex/face self contacts |
| `physics/3d/solver/soft_body_self_collision_compliance` | 0.000001 | Normal XPBD softness |
| `physics/3d/solver/soft_body_self_collision_friction` | **0** | Coulomb-like friction coefficient; 0 disables extra work |

Example experiment for cloth with folds: thickness `0.01` m,
compliance `0.000001`, friction `0.5`. Recreate a physics space
to adopt ProjectSettings changes (values are cached once per space).

## How it works

For an already-gathered non-adjacent vertex/triangle contact, the normal
solver runs first, accumulating a **nonnegative normal XPBD multiplier**.
A single optional tangential pass then:

1. Reprojects the vertex onto the *current* face and computes barycentric
   weights `(a,b,c)`, using the existing checked self-collision narrowphase.
2. Forms relative displacement between the vertex and the barycentric
   triangle point **over the current step** from positions `x` and `q`.
3. Removes the normal component, obtaining a tangential slip vector `t`.
4. Forms effective inverse mass `W = inv_m_v + a² inv_m_a + b² inv_m_b +
   c² inv_m_c` and computes the friction impulse

   ```text
   impulse_t = -t * min(1 / W, (mu * lambda_normal) / |t|)
   x_v      += inv_m_v * impulse_t
   x_face_i -= inv_m_i * barycentric_i * impulse_t
   ```

The cap `|impulse_t| <= mu * lambda_normal` approximates a Coulomb cone.
It does **not** accumulate a persistent static-friction multiplier, and
does not yet distinguish static/dynamic material coefficients. It is
a local position-based model, not a full continuum Coulomb contact law.

All four new positions are checked before committing any update.
Pinned vertices do not move. Internal contacts with all four vertices
free preserve linear momentum under the barycentric approximation; a pin
transfers reaction to its external attachment. The contact separation
remains unchanged to first order because the correction is tangential.

The tangential pass runs **after** the existing self-collision XPBD normal
iterations and **before** SoftBody3D reconstructs velocity from positions.
Applying friction directly to `node.v` at this point would be overwritten
by the velocity reconstruction.

## Performance and limitations

No additional broadphase, candidate query, persistent buffer or per-contact
heap allocation is introduced. With friction set to zero, the existing
normal collision path skips the extra traversal entirely. When enabled,
the additional work is O(number of already-gathered contacts), still
bounded by the existing 65,536 contact-pair budget.

This extends discrete vertex/face contacts only: it does **not** add swept
continuous self-collision, edge/edge contact friction, collisions between
different soft bodies, or robust behavior for deeply interpenetrating cloth
and degenerate triangles. Multiple contact order can influence the result.

## Verification

```bash
python3 -m unittest discover -s tests/stress -p test_physics_xpbd_self_friction.py -v

# With a native tests=yes Cgame build:
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test \
  --test-case="[PhysicsSelfFriction]"
```

For runtime evaluation, simulate folded cloth with moving/pinned faces
and sweep friction `0, 0.1, 0.5, 1.0` at multiple physics tick rates.
Compare p95/p99 physics-step time, RSS, remaining tangential slip and
contact-pair count. Do not claim a speedup or physical equivalence to
full Coulomb friction based solely on source contracts.
