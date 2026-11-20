# Personal island waypoints (connected client)

Press **J** in the connected game client to open the whole-island map. Left-click
inside the playable island to set or move one personal waypoint; right-click the
map to clear it. The map draws a golden pin and a line from the survivor to the
chosen destination. A live eight-way compass heading and distance in metres are
shown underneath the map.

The compact north-up survival radar uses the same coordinate as a golden beacon
when the destination is within 72 metres, or a golden direction arrow at its edge
when farther away. Caravan, escort, rally and ruin-survey markers remain distinct.

Waypoints are purely **client-side navigation**: they are not broadcast, do not
alter movement or world authority, and are not stored in character saves. They
are cleared when the connected game client restarts. Coordinates outside the
generated island, malformed numbers and clicks outside the map panel are ignored.

Implementation: `scripts/client/world_map.gd`,
`scripts/client/survival_radar.gd`, and the common validation and projection in
`scripts/shared/travel_navigation.gd`. No engine extension or additional RPC
is required. The standalone offline preview uses a separate interface and does
not expose the full-island map.

Regression:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Suite: `res://tests/test_personal_waypoint.gd`.
