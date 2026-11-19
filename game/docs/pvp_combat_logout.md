# PvP combat disconnect safety

When a confirmed damaging PvP hit occurs in the red or black full-loot
zones, both live participants receive a **30-second server-owned combat
tag**. The HUD shows how many seconds remain. Misses, zero damage, party
friendly-fire blocks, safe-zone attacks and PvE do not set this timer.

A survivor who disconnects while alive and combat-tagged **inside a
full-loot zone** incurs one normal full-loot death: carried equipment
and currency are placed into a public world bag, the private account
stash is retained, and the survivor is respawned with a starter kit
before their account save is serialized. Leaving the dangerous zone
and reaching protected sanctuary, or waiting for the tag to expire,
allows ordinary safe logout. The server treats voluntary departure and
network loss consistently. The rule is intentionally strict for this
PvP-focused prototype; a future grace-period combat ghost can improve
tolerance of accidental connection drops.

No tag time, damage or logout decision comes from the client. The
dedicated network layer applies the penalty **before** capturing the
Nakama character save to prevent copied equipment after dropping gear.
The server's generic remove_player also invokes the same idempotent
check for callers that bypass Net.leave. Transient tag state is not
written into character saves, so old profiles need no migration.

Loot bags are world-session objects and are not part of the existing
server barricade-only checkpoint; a full host restart may destroy
uncollected PvP drops. Run game/tests/test_pvp_combat_logout.gd.
