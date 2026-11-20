# Wading and soaking in shallow water

The same shallow coastlines and fords that movement already allows now physically soak a survivor's clothing.

- Immersion depth is measured from **server-owned terrain height** relative to world sea level. Only passable water (0–1 m deep) counts.
- Even without rain, remaining in shallow water adds moisture at `1 + 4 × depth_metres` percentage points per second. Water depth, rather than buttons, determines the rate. Wetness cannot exceed 100.
- Physical immersion prevents campfires and overhead weather tarps from making a standing-in-water character drier. Rain can still add to wetness.
- Once on dry ground, existing rain ingress, air drying, shelter drying and campfire drying remain unchanged.
- The existing cold/wetness and regional wind-chill calculations use the new moisture. Thus wading into cold water makes subsequent travel more dangerous.
- The server replicates a **self-only** `wading_depth_m` HUD hint; it does not accept any water depth or moisture value through RPC.
- Moisture already persists using character saves; no new save format, inventory items, commands, or Godot engine modifications are needed.

`game/tests/test_wading_wetness.gd` is included in `game/tests/run_all.gd`. The tests cover terrain validation, rate limits, soaking despite shelter/fire, live shore immersion and relog persistence.
