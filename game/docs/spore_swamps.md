# Spore swamps and sealed suits

A survival-biome risk inspired by post-apocalyptic scavenging, integrated with Albion-style tiered crafting.

## Rules
- Only natural **swamp biome** positions outside the settlement and green zone produce airborne infected spores.
- Server-authoritative exposure adds **0.14 infection/second by day** and **0.28 infection/second at night**, until the existing infection cap. Other biomes, safe areas, dead survivors, and invalid positions cause no new spore exposure.
- Infection uses the **existing persistent wound system**, including antibiotics, field antiseptic and serum. No new save field or schema migration is required.
- **Sealed Expedition Suits T2, T3 and T4** are bench-crafted from same-tier cloth, bars and fiber. Their spore resistances are **65%, 75% and 85%**. Unlike ordinary jackets, they have low combat armor and modest climate insulation.
- Only a suit actually **owned and equipped** on the authoritative server grants protection. Spoofed client inputs and stale equipment slot IDs cannot reduce infection.
- Snapshots include a `you.spore` state (active, rate, protection). The main HUD and F3 details show danger and filtration. Enter/exit announcements are edge-triggered, not spammed every tick.
- Existing character saves and old equipment remain compatible.

## Test
Run `godot --headless --path game --script res://tests/run_all.gd`. `test_spore_hazard.gd` covers biome safety, day/night rates, tier recipes, equipment verification, real-world exposure, warnings and save persistence.
