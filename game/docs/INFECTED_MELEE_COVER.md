# Infected melee cover and breach pressure

Ordinary infected melee attacks now respect the **same real solid geometry**
as sight acquisition and projectiles. Walkers, runners, brutes, spitters
in close claw range, and elites cannot reach players through rocks,
ruins, trees or player-built barricades.

A blocked attack does **not** spend the attack cooldown, award a hit,
cause bleeding, infection, fractures, spend armor plates or activate
parry/interception. Instead the infected stays in CHASE, faces the
survivor and pushes into the obstacle. The existing collision/stuck
timer drives the authoritative barricade damage loop, preserving
survival siege pressure. The player must still leave cover or defeat
the attacker. Raid bosses preserve their established melee and
telegraphed encounter rules; spitter acid AoE uses its existing
ground-warning and splash rules.

The server checks the line twice: at AI strike selection and before
the damage/wound pipeline. Both reference only server positions and
world blockers. No new client action or RPC can forge an attack.
Interest-limited snapshots carry one boolean `melee_blocked`, used
for a `BLOCKED` enemy indicator and amber visual tint online,
and the same tint in solo mode.

Regression coverage:
`res://tests/test_infected_melee_cover.gd` registered in `run_all.gd`.
Run `godot --headless --path game --script res://tests/run_all.gd`.
