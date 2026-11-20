# Ranked training duels (Elo arena preview)

The safe green hub supports both casual training and optional **ranked
challenges**. Only both players' authenticated Nakama account IDs can
enter a rated fight. A challenge must be accepted by the recipient, and
the same pair of account IDs cannot earn a new result more than once every
20 minutes within a dedicated-server session. Guests cannot enter ranked
mode. Reusing network peer IDs or swapping attacker/victim orientation
does not bypass this restriction.

A confirmed nonlethal knockout scores the rated match using deterministic
K=32 Elo. A voluntary surrender or disconnect forfeits the encounter.
Expiry or leaving the hub ends it without a ranked result. Ratings begin
at 1200 and stay within 600–2400. Players receive individual win/loss
records and visible Bronze/Silver/Gold/Platinum/Diamond tiers, with
exact rating numbers visible to their own account. Casual duels remain
non-rated. Neither mode awards real PvP honor, loot, infamy, XP or deaths.

The server owns the result and updates both character records before
sending private finish events. Both Elo and win/loss counters are saved
in strict validated version-one character data; older saves default to
1200, 0 wins, 0 losses. On logout the network layer resolves a ranked
disconnect forfeit **before** taking the final save snapshot, avoiding
a stale rating being restored after leaving. The pair-cooldown ledger
is intentionally session-only and not a season-wide global ladder.
Regression coverage: `game/tests/test_ranked_duels.gd`.
