# Cgame: experimental CPU soft–soft particle contacts for Jolt

Jolt Physics provides soft–rigid contact handling but has no built-in
soft-body versus soft-body collision response. Bullet has broader soft-soft
handling, including vertex/face and deformable cluster approaches.

Cgame adds an *opt-in, deliberately bounded* CPU **particle/particle**
approximation for interactions between active soft bodies in a single space.
It does **not** collide soft-body triangles with particles, so sparse meshes
can intersect despite this feature. This is a first stage toward more
complete soft–soft collisions, not a replacement for Jolt's collision system.

## How it works

Before Jolt's physics `Update()`:
1. Enumerate active Jolt soft bodies when opt-in is enabled.
2. Filter collision layers/masks and explicit collision exceptions.
3. Filter by overlapping world AABBs expanded by contact radius.
4. For each surface particle pair within radius, compute a separating
   normal (with deterministic fallback for coincident particles).
5. Apply a two-body inverse-mass-weighted velocity impulse, a bounded
   Baumgarte separation bias, and Coulomb-limited sliding friction.
6. Bound body-pair and particle-pair checks to prevent unbounded work.

The implementation uses the particles' world-space rotations and
double-precision COM position **differences** for large-world precision.
Relative impulse updates are transformed back to particle-local velocities.
Interior tetrahedral centroid particles are explicitly excluded.

## Settings

Project Settings → Physics → Jolt Physics 3D → Simulation:

- `soft_body_soft_contacts = false` (default; no contact loops).
- `soft_body_soft_contact_radius = 0.1` (0..1 m), particle proximity
  threshold; larger values give thicker, less precise collision shells.
- `soft_body_soft_contact_recovery = 0.2` (0..1), controls velocity bias
  against penetration.
- `soft_body_soft_contact_friction = 0.2` (0..1), Coulomb friction
  coefficient applied to each particle pair.
- `soft_body_soft_contact_max_particle_pairs = 32768` (1024..65536),
  maximum particle-pair tests per physics step. Body candidate checks are
  additionally capped at 2048 per step.

Limits are global to the world/space, not per body. When a budget is
exhausted, subsequent candidates are skipped for that step; scene ordering
can therefore affect which contacts are handled under extreme load.
The default-off mode runs just a branch and preserves existing physics
behavior.

## Limitations

- Discrete vertex-to-vertex tests only; sparse meshes can miss contacts.
- Not continuous collision detection: fast motion can tunnel between ticks.
- No triangle intersection, volumetric interpenetration, contact manifold,
  cluster collision, persistent warm starting, or restitution.
- Only active soft bodies are checked; sleeping bodies are not scanned.
- Contact response is a *pre-step velocity* correction, not a positional
  XPBD projection. Strong existing penetration is only gradually resolved.
- CPU cost is O(Va * Vb) per overlapping body pair, but hard capped; under
  stress bodies beyond the budget can skip contact response entirely.

## Checks

    python3 -m unittest tests/stress/test_jolt_soft_soft_particle_contacts.py -v

Native Cgame Jolt fixture:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
        --path tests/stress/jolt_soft_soft \
        --script res://soft_soft_particle_regression.gd

This fixture compares an allowed interacting pair to a second pair
which has both collision masks disabled. It also checks pinned particles,
finite coordinates, and finite bounds.

Benchmark with 2, 8, 32, and 128 soft bodies, varying vertex counts;
track physics step duration, peak resident memory and skipped work when
budgets are exhausted. Run both with this feature disabled and enabled.
Do not claim a performance win without measured baselines.
