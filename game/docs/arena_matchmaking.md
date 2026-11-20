# Opt-in rated arena matchmaking

The safe-hub arena now offers a bounded automatic queue alongside
direct casual/ranked challenges. Players must explicitly join and hold
an authenticated Nakama account. Two matching queued survivors count as
mutually consenting; the server starts a regular validated ranked duel
using the existing invitation/acceptance path. Damage, knockout and Elo
settlement remain server-authoritative. No equipment loss, PvP infamy,
open-world honor, or real deaths are awarded in the hub.

Candidates must still be alive, in green-zone safety, untagged by PvP,
within eight metres, not already dueling or handling another invitation,
and outside the existing 20-minute account-pair rematch lock. The server
looks for the closest Elo match. Initially it allows a ±125 rating gap;
the acceptable difference grows every 20 seconds (maximum 350) for
players who have waited. Queue size is capped at 64 players; pairing
runs every ten server ticks. Searching ends on match, cancel, disconnect,
leaving the hub, dying, combat tag, or conflicting invitation.

The inventory panel offers Find rated opponent and Leave arena queue
controls plus a private search timer and Elo range. Account identity and
queue ownership are validated server-side; a reused ENet peer ID cannot
inherit another player's consent. Queue state is transient and is never
stored in character saves. No new Cgame core engine interfaces required.

Regression: `game/tests/test_arena_matchmaking.gd`.
