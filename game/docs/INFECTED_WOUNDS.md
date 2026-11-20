# Injured infected behavior

Critical wounds now change the live, server-controlled infected movement at
35% health or below. Normal walkers and spitters **limp** (65% base movement
speed), while runners make a dangerous **final sprint** (118% base speed).
Elite infected receive smaller adjustments: 82% and 109%, respectively.
Brutes and raid bosses ignore these ordinary wounded-gait rules.

The mechanic runs in the existing `Zombie._move_toward` movement path for
chase, search and roaming. It cannot alter damage, attack cooldowns, PvP,
safe-zone acquisition, knockback, snare or hit authorization. The server sends
an observable `wound_phase` to nearby clients in normal world snapshots.
Online rendering colors wounded infected and shows LIMP/FRENZY above the health
bar. Solo-preview boxes update their individual colors without modifying
shared materials.

Regression suite: `res://tests/test_infected_wounds.gd`, registered with
`res://tests/run_all.gd`.
