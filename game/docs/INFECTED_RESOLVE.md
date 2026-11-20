# Diminishing returns on infected stuns

Server-confirmed melee stuns now have a short-lived **resolve** window.
The first effective stagger has its full original duration; a second
effective application within six seconds uses 65% duration; third
and later applications use 40%. Elites still halve these durations.
Unsuccessful refreshes do not add resolve, refresh its expiry or cancel
an ongoing acid-spitter windup. After six seconds without effective
stagger, the target returns to full vulnerability.

Raid bosses stay immune to this PvE stun. Players, PvP, knockback,
snare and armor mechanics remain unchanged.

Nearby clients see a `RESIST` marker and purple tint once resistance
reaches two effective staggers, via the existing interest-limited snapshot.
Solo preview uses the same data. All timers and stack counts stay on
the server; no new RPC or save-file fields are required.

Regressions: `res://tests/test_infected_resolve.gd` via `run_all.gd`.
