# Bullet-inspired anisotropic contact friction (GodotPhysics3D)

This optional extension uses an **elliptical static and kinetic friction
cone**, so sliding along a preferred world axis can have higher resistance
than sliding across that axis. It supports directional floor materials,
textured conveyors, anisotropic surface strips, and experimental tire-like
contact behavior. This is a *global, world-space axis*, not a per-body local
material axis, and is NOT a physically complete brush tire model.

Project Settings:

- \`physics/3d/solver/friction_anisotropy_ratio = 0.25\`
  means transverse resistance 25% of resistance along the preferred axis.
  Default **1.0**, preserving legacy isotropic Coulomb friction, with no
  extra ellipse calculation or contact buffers.
- \`physics/3d/solver/friction_anisotropy_axis = Vector3(1, 0, 0)\`
  specifies preferred direction **in world coordinates**. The projection
  onto the contact tangent plane is normalized. Contacts where the axis
  is almost parallel to the normal fall back to isotropic friction.
- The usual \`physics/3d/solver/static_friction_multiplier\` sets the
  larger static cone (default 1.0). Static-to-kinetic breakaway is applied
  in elliptical contact coordinates.
- Existing \`physics/3d/solver/stribeck_transition_velocity\` remains
  compatible: when enabled, the Stribeck-adjusted friction coefficient is
  used as the ellipse size, with the static multiplier passed as **1**
  to avoid counting the static friction twice.

For tangent impulse J decomposed into preferred direction u and tangent
perpendicular v, with dynamic friction load L = mu * normal_impulse:

\`q² = (dot(J,u)/L)² + (dot(J,v)/(L*ratio))²\`.

If \`q <= static_multiplier\`, keep J. Otherwise scale the whole impulse
by \`1/q\` (project to the kinetic ellipse). This radial projection
is consistent with the existing sequential impulse approach but is not
a full maximum-dissipation optimization.

Scope:
- Rigid-rigid and rigid-soft contacts in **GodotPhysics3D**.
- Cached warm-start impulses are clamped to the current static ellipse,
  preventing stale lateral impulses when material settings change.
- 3D only; Jolt and GodotPhysics2D remain unaffected.
- No per-contact allocation. Additional dot/cross/scaling operations
  only execute when anisotropy ratio is under 1.
- The helper uses double intermediates for extreme contact impulses.

Run the source + numerical contracts:

\`python3 -m unittest discover -s tests/stress -p 'test_physics_anisotropic_friction.py' -v\`

C++ doctest:
\`tests/servers/test_godot_physics_contact_anisotropic_friction.cpp\`

Next steps: introduce true *per-material* local anisotropy and oriented
contact friction for articulated wheel/contact patches.
