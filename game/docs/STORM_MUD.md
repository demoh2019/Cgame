# Regional storm mud and roads

Rain now has a movement trade-off in the survival MMO world instead of affecting only exposure, stealth and campfire fuel.

- While **outside in regional storms**, all on-foot movement loses between 7% and 18% speed depending on biome. Bicycle movement loses between 9% and 24% on top of its existing terrain and tire-grip modifiers.
- Established roads prevent up to 85% of the **additional rain loss**. Road speed bonuses, weight, injuries, stealth, weather temperature and existing bike traction otherwise remain intact.
- Dry conditions and safe hub shelter maintain current movement speed. This is **live weather**, not a persistent dirty-shoes item or permanent terrain mutation.
- Server movement calls `StormMud.factor(world, player.position, time, mounted)` and never accepts a network-supplied mud multiplier. Client prediction reuses the replicated clock and seeded world; pending input replay retains the time used to predict that step.
- The player's own snapshot contains `storm_mud_factor` for weather feedback. This is not revealed as private movement or account data to other clients.
- There are no new RPC commands, inventory/save migrations, or engine changes.

Regression: `game/tests/test_storm_mud.gd`, included in `game/tests/run_all.gd`.
