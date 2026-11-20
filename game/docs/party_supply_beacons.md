# Temporary supply beacons

The main online client now shows an actionable **party supply beacon** when a current teammate requests food or water. Previously, the request produced only a chat message with coordinates. The latest accepted alert appears as an amber icon on the island map (J) and a floating beacon at the server-issued location in the 3D world. Its label shows the requested supply and the seconds remaining.

A server-authorized `party_supply_request` event includes a 45-second expiration measured on the authoritative simulation clock. The client retains only the latest valid request and uses regular snapshots to check both expiration and party membership. Switching groups, a member leaving, the timer expiring or reconnecting clears access to the old signal. The map never adds it to discovery, permanent waypoints, the public event stream or saved character state.

The client does **not** accept a request position, duration or membership from the local player. The server continues to enforce genuine hunger/thirst and a 30-second per-survivor request cooldown. Only existing group members receive the event. Team members can travel to the location and use the existing **Party → Aid / Share** action to help.

No native engine changes or save migrations are necessary.

Regression coverage: `game/tests/test_party_supply_beacon.gd` exercises exact expiry, outsider and old-party privacy, invalid data, real authoritative event generation, client receipt and reconnect clearing.

```sh
godot --headless --path game --script res://tests/run_all.gd
```
