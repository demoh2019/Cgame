# Trail Tire Grips – off-road traction for bike expeditions

The existing terrain-aware salvaged bicycle now has an optional crafted, short-lived tire upgrade. This connects Albion-style specialization to Days After survival scavenging, without giving riders a universal speed boost.

- Craft `trail_tire_grips` at a workbench: **2 Cloth T2 + 2 Fiber T2 + 2 Scrap**.
- Own a real `salvage_bike`, **dismount** and consume one set of tire grips. It lasts **240 seconds**, even after leaving and rejoining the server.
- On swamps, beaches, forest roots and mountain scree, the kit restores **half of the biome traction loss** (swamp 0.56→0.78; beach 0.72→0.86; forest 0.90→0.95; mountain 0.78→0.89). Firm ground retains its normal speed; uphill drag, collision, water limits, weight, injury and on-foot movement are unaffected. It does not suppress bicycle noise.
- The server consumes the item, owns the buff, applies it only to validated mounted input, bounds the timer, rejects invalid saved state and clears the effect on respawn. No stacking or renewing while active.
- Both authoritative simulation and client prediction/replay use `Movement.step` and `BikeTerrain.speed_factor` with the server-replicated timer. The client cannot send its own speed or grip duration in the movement RPC. Existing item-use RPC and inventory UI are reused.

Regression coverage: `game/tests/test_bike_grip.gd` registered in `game/tests/run_all.gd`. Run: `godot --headless --path game --script res://tests/run_all.gd`.

This upgrade composes with seeded dirt-road traction: roads keep their existing travel bonus and do not become a universal grip multiplier.
