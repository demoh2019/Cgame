# Caravan compass and private party navigation

Roads and world-generated settlements are useful only when survivors can
follow their objectives without memorizing coordinates. The existing
north-up survival radar now shows two additional waypoints:

- **Teal** — your own active NPC caravan delivery destination. When it is
  farther than 72 m, a teal arrow points along the radar rim toward the
  destination; inside 72 m, a ring and dot show the exact target.
- **Amber** — your party leader's live, temporary rendezvous point. It has
  the same near/far marker behavior; only members of that party see it.
- The caravan panel now shows **remaining straight-line distance** in
  meters and a true eight-point compass heading (N, NE, E, SE, S, SW,
  W, NW) next to the required cargo, destination name and payout.
- Distance updates with the live position. This is a direction to the
  target, not an invented road distance or estimated travel time.
- The radar pulls only the active actor's server-owned `caravan_view`
  and the party-member-only `Parties.state_for` marker, or the
  corresponding private online snapshot. It never looks through
  nearby enemy inventories or other players' private assignments.
- Invalid, missing and nonfinite coordinates are silently rejected
  before geometry is drawn. The radar edge pointer remains clipped
  inside its circle for any travel distance.
- Existing ruin-survey radar marks, party standards, NPCs, crafting,
  PvP and caravan rewards are unchanged. No engine modification needed.

Regression: `game/tests/test_travel_navigation.gd` in
`game/tests/run_all.gd`.
