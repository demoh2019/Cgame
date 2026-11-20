# Find your lost backpack in dangerous zones

When a survivor dies and drops their entire inventory in a **red or black
full-loot zone**, the existing real, publicly lootable death bag now also
creates an owner-only **LOST BACKPACK** navigation target. It bridges
Days After corpse-run recovery with Albion-style lethal open-world PvP.

- The death bag itself is unchanged: the full backpack drops once into a
  normal public loot bag with a 300-second lifetime, ordinary corpse scent,
  and **no protection from other players**.
- The server tags that existing physical bag with the original survivor's
  authenticated account identity, or an unforgeable live guest session
  identity. Neither this token, other players' locations, nor the dropped
  item list is sent to the client as a recovery marker.
- The owner's private `you.death_recovery` snapshot contains only ground
  coordinates and the **true remaining lifetime** while their latest
  surviving tagged bag still exists.
- The expedition atlas includes a clickable orange LOST BACKPACK objective.
  Selecting it updates the normal full-map waypoint and the smaller tactical
  radar. The radar also draws the private beacon directly, even offscreen.
- The HUD shows distance, bearing and seconds left. If the bag is fully
  looted by anyone, its contents run out or its lifetime expires, the next
  snapshot clears the target and an automatically followed waypoint is
  removed. Partial loot leaves the target until the bag truly empties.
- Registered accounts reconnecting to the **same live server** can still
  locate their old bag while it exists. Reusing a guest's network peer ID
  never transfers someone else's private waypoint.
- Deaths that do not drop items create no marker. There are no free returns
  or item duplications and no newly introduced survival or engine bypasses.

World bags are server-session state, not durable global storage: a complete
server shutdown does not preserve corpse bags or their recovery markers.
This change intentionally does not pretend otherwise.

Implementation: `scripts/shared/death_recovery.gd`,
`scripts/server/game_server.gd`, `scripts/shared/expedition_atlas.gd`,
`scripts/client/world_map.gd`, `scripts/client/survival_radar.gd`,
`scripts/client/hud.gd`.

Tests: `tests/test_death_recovery.gd`, registered in
`tests/run_all.gd`.
