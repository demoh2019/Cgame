# Protected training duels

Two survivors can voluntarily spar inside the green hub. A challenge
requires proximity (8 m), lasts 20 seconds and cannot be spammed more
often than once every 8 seconds. The recipient must explicitly accept;
no spectator, alt account or PvP-tagged combatant can create a match.
Each match lasts at most 120 seconds and ends automatically on leaving
the hub, moving more than 25 m apart, death, disconnection, surrender or
knockout. The server caps training hits at 1 HP and restores health
lost to the duel. No equipment is lost, no PvP/ordinary kills, honor,
criminal infamy, combat-logout tags, bleeding or skill XP are awarded.

Only the matched opponent bypasses protected-hub hit filtering; open
world guild-friendly-fire, party-safe and full-loot PvP rules are unchanged.
Both client commands and owner snapshots are backed by authoritative
peer-instance checks. Invites and matches never persist in character saves,
preventing a recycled peer ID from inheriting a stranger's duel.

Online inventory provides Challenge, Accept and Decline/end buttons using
the nearby survivor selector and shows private duel state. Run
`game/tests/test_training_duel.gd` from the shared headless suite.
