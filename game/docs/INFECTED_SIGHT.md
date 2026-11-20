# Infected line-of-sight and destructible cover

Unalerted walkers, runners, brutes and spitters now acquire survivors by
**sight** only across a clear line in the real shared 2D world. Tree trunks,
ruin solids and player-built barricades use the same authoritative intersection
logic that already blocks projectiles. A quiet survivor on the other side of
a barricade can stay unseen until they move into the open or the wall breaks.

Other senses remain deliberately independent of cover: sprinting, gunshots
and bleeding can reveal players behind walls. Firelights and flares are visual
cues and require a clear sight line. Safe-zone and dead-player checks still
run first. Once a creature has valid combat aggro, takes damage, is taunted
or receives a genuine pack warning, a wall does not erase its memory; the
existing chase leash and investigation timeout still govern disengagement.

The sight ray runs at the existing ~4 Hz target acquisition cadence, only
for candidates within visual range that are not already sensed by noise or
blood scent. No new client permissions, persistence fields or engine
modifications are needed: the shared RangedCover helper is reused.

Regression coverage: `game/tests/test_infected_sight.gd` (geometry,
senses, safety, pack alert, active combat, and a live dynamic barricade).
Run `godot --headless --path game --script res://tests/run_all.gd`.
