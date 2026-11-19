# PvP Honor and separate character rank

Real server-confirmed player kills in red and black zones now advance an
independent **PvP kill counter** and **honor**. Red-zone victories award
4 honor; lawless Black Zone victories award 10. The attacker receives
honor for the same victim account only once per 300 seconds, but every
legal death remains counted as a real PvP kill.

Anti-farm tracking uses stable account identity or unique guest-session
identity (never recyclable peer IDs). The bounded recent-kill ledger is
session-only; it resets on full server restart. Killing another character
from the attacker's own account grants no honor or PvP kill credit.

Honor unlocks Wanderer, Contender, Veteran and Champion ranks, visible
to nearby players, while the owner's HUD receives exact honor and PvP
kill totals. Honor is independent of the existing PvE renown discounts
and existing red-zone PvP infamy, outlaw status and price penalties.
Honor is validated strictly in the existing character save format, with
migration defaults for old version-one characters. All events are sent
only to the credited killer. Regression: `test_pvp_honor.gd`.
