# Raid boss reinforcement phases

The existing 600-HP party raid boss now summons genuine infected at two
health thresholds. At 65% HP the server calls up to two runners; at 30%
HP it calls a brute and a runner. Existing one-time **enrage** and
telegraphed ground slam attacks continue independently. This gives
groups more to coordinate: positioning, area awareness, target priority
and sustained damage rather than a pure single-target damage race.

The dedicated server owns all phase and spawning decisions. Each phase
can activate once per encounter; no client command can summon attackers.
Sites must remain in the boss's risky region on walkable terrain, clear
of players and other infected. The global infected cap is respected, and
limited space can reduce wave size. Reinforcement alerts are interest
filtered for nearby clients. After victory or an expired raid, leftover
summons vanish and cannot generate new drops. Boss loot reservations,
party mastery and other combat rules remain unchanged.

Regression: `game/tests/test_raid_reinforcements.gd`. This is session
state and does not require new Cgame engine primitives or save changes.
