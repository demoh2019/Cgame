# Water-depth movement and sprint eligibility

Shallow coastal crossings now cost time, creating meaningful path choices alongside persistent wet clothing and wind chill.

- On foot, 0–1 m of passable water applies up to a **35% travel slowdown**. Bicycles lose up to **45%** of speed from water drag on top of biome grip and road/weather handling.
- Deeper than 0.25 m water, **sprint is disabled**. The authoritative server checks the terrain before calling its stamina-spending sprint function; blocked sprint neither drains stamina nor grants athletics XP.
- Shared `Movement.step()` applies identical depth-derived speed and sprint eligibility to server and client prediction. Input replay recomputes eligibility at its replayed position. Clients cannot send a water-depth or drag multiplier.
- Dry movement is unchanged, deep water remains collision-blocked, and already existing wet-clothing/cold hazards continue to apply without save migration.
- Existing coastal depth HUD tells players when a crossing slows them, and movement/collision remains entirely within standard Godot scripting.

Test: `game/tests/test_wading_travel.gd`, registered in `game/tests/run_all.gd`. Covers dry/ankle/knee/waist water, bicycles, forged sprint flags, invalid coordinates, real shoreline/server movement, and stamina/XP integrity.
