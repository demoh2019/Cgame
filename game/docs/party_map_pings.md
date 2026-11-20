# Party tactical map pings

**Online:** open the map with **J**; **Shift + left-click** a spot inside
the island to share a **teal** tactical pin for 30 seconds with your current
party. Teammates see the pin on their map and radar (including a direction
arrow for destinations beyond radar range). Unlike the leader's existing
rally, any living party member may place a ping remotely.

Ordinary left click still sets your **private gold waypoint**, and
right click clears only that private waypoint. Party pings never change
player destinations or move characters.

## Authority and privacy

- At least two authenticated members in a real server party.
- World coordinates must be finite and within the island radius.
- One party-shared marker; **6s group-wide cooldown**, **30s duration**.
- Server uses trusted RPC sender identity, never a claimed peer ID.
- Validated private `you.party.ping` snapshot only: no public nearby
  entity, public map event, character save, loot, XP or discovery leak.
- Leaving/disbanding, dying, and expiry clear pings without a replayable
  reward. The server's regular command flood limiter applies too.

Regression coverage: `res://tests/test_party_map_ping.gd`, in the
headless `res://tests/run_all.gd` suite.
