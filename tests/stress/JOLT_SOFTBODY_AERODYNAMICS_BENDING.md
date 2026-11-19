# Jolt: aerodynamic drag and optional XPBD bending

## Motivation and scope

Cgame's GodotPhysics3D backend already applies two-sided quadratic surface drag
to SoftBody3D. Its Jolt backend previously ignored SoftBody3D.drag_coefficient.
It also always requested EBendType::None when creating XPBD constraints, despite
Jolt supporting distance and dihedral bend constraints.

This change does not import/copy other engines' source code. It uses features
already provided by Cgame's vendored Jolt Physics.

## Aerodynamics

For each nondegenerate face of area A, unit normal n, and mean vertex
velocity v, Jolt applies an additional nodal impulse along n:

    vn = dot(n, v)
    J_unclamped = -drag_coefficient * A * dt * vn * abs(vn) / 6

The /6 distributes the standard 1/2 * area * vn^2 quadratic surface force
across 3 vertices. Air is assumed stationary; the project's existing Area3D
wind forces are still calculated separately.

To avoid destabilizing high-speed or high-drag cases, the absolute impulse
applied to each vertex of a face is capped:

    abs(J) <= 3 * abs(vn) / (inverse_mass0 + inverse_mass1 + inverse_mass2)

This cap prevents a single face drag impulse from reversing the face's
average normal velocity, although multiple faces may interact during a step.
Pinned vertices (zero inverse mass) receive no velocity change.

The same face loop handles wind and drag, avoiding an additional O(faces)
traversal when both are enabled. No extra face loop runs when drag is zero
and no wind affects the body. There are no new per-frame allocations.

## XPBD bending

Project Settings > Physics > Jolt Physics 3D > Simulation:

- `soft_body_bend_mode`: 0 = Disabled (default, backwards compatible),
  1 = Distance, 2 = Dihedral.
- `soft_body_bend_compliance`: nonnegative inverse stiffness (default 0.001).
  Lower compliance produces stiffer bending; zero requests rigid bending.

Bend constraints are generated when the soft body shared settings are created.
Changing the project setting does **not** retroactively rebuild an existing
SoftBody3D: recreate its mesh/body to apply the new value.

Distance mode creates simple bend distance constraints; Dihedral mode
preserves the relative angle between adjacent triangles, including curved
rest shapes, at a higher CPU cost.

## Validation

Mathematical/source regression (no engine binary required):

    python3 -m unittest tests/stress/test_jolt_softbody_aerodynamics.py -v

Native regression requires a compiled Cgame editor with Jolt enabled:

    ./bin/godot.linuxbsd.editor.dev.x86_64 --headless \
        --path tests/stress/jolt_physics \
        --script res://softbody_aerodynamics_regression.gd

The test project explicitly selects Jolt, opts in to dihedral XPBD bending,
tests zero/moderate/extreme drag, both positive and negative velocity,
getter round-trips, and finite mesh bounds and vertex coordinates.

For performance comparisons use the same host, Cgame binary, mesh, physics
timestep, and release build. Compare drag=0 and drag>0, plus bend modes
Disabled/Distance/Dihedral. Record frame time, allocations and peak RSS
at increasing mesh resolutions. Source inspection alone is **not** a proof
of better FPS or completed native runtime validation.

## Important limitations

This is a lightweight aerodynamic force model, not a fluid simulator:
there is no vortex shedding, air pressure field, fluid-structure coupling,
soft-soft collisions or FEM volumetric elasticity. Jolt's current
soft-body collision limitations still apply.
