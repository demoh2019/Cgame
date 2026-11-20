# Cooperative survival supply requests

The **Party** section of the main game HUD now offers **Request food** and **Request water** next to **Aid / Share**. A player who is actually hungry or thirsty (60/100 or lower) can alert their current group; teammates receive a private message with the requesting survivor's name, measured stat and current server-owned x/z location. Walk to them and use **Aid / Share** to give food or water.

## Rules and privacy

- The server verifies the requesting character is alive, belongs to a group of at least two, and really needs the chosen supply. The client selects only `food` or `water`.
- A successfully sent request starts a 30-second per-player cooldown shared between food and water. Invalid/healthy/solo requests do not consume the cooldown.
- Signals do not consume items, move players, change inventory, or grant bonuses. Their purpose is coordination around the existing paid supply-transfer mechanic.
- Event delivery is limited to **current** party members other than the caller. The group is rechecked at transmission time; leaving the group revokes queued location visibility. There is no persistent public world marker.
- The request cooldown is in memory for the current character session; there is no save migration or engine change.

## Verification

`game/tests/test_party_supply_request.gd` covers server policy, low-stat checks, spam cooldown, authentic position, RPC presence, party privacy, member departure and death. The existing test runner discovers the new suite.

```sh
godot --headless --path game --script res://tests/run_all.gd
```
