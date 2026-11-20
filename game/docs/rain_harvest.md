# Field rainwater harvesting

Weather is now a resource opportunity as well as an expedition danger. Inspired by survival crafting in post-apocalyptic games, the process uses the existing deterministic climate system, not client-authored weather.

## Player flow

1. Craft an **Expedition Rain Catcher** (`rain_tarp`) anywhere from 2 Cloth T1, 2 Fiber T1 and 1 Plank T1.
2. Travel outside the safe settlement and wait for an actual storm on dry, reasonably level ground. The inventory action **Collect rainwater** consumes one tarp and yields exactly 2 clean water bottles.
3. Swamp rain is contaminated: additionally requires one physically carried `charcoal_filter`. Missing filters or missing tarp block the entire transaction without spending anything.
4. Wait **90 seconds** between collections. The dedicated server owns the clock and persists the remaining cooldown; legacy characters load with no cooldown.

## Trust and balance

- No client weather, yield, filter flag, map position or quantity is accepted.
- Server checks live world seed, storm phase, shelter, water, terrain and biome.
- A trial inventory performs every debit and credit before committing. The real inventory is unchanged if it would overflow.
- Tarp is consumed. Crafting inputs cost more than retail water, preventing a self-sustaining material or silver loop.
- Rewards are ordinary water bottles, compatible with existing hydration, medical crafting, trading, stash and full-loot rules.
- Snapshot contains `you.rain_cooldown`; UI shows harvest result and remaining timer. Current account saves use the same version-one schema.

## Tests

`godot --headless --path game --script res://tests/run_all.gd`

`test_rain_harvest.gd` covers authentic climate, terrain, safe zones, filtration, crafting, inventory atomics, live world integration, server cooldown, snapshots, malformed saves and legacy migration.
