# Healer threat — tactical party PvE

Classic MMORPGs make it meaningful for a tank to guard the medic. Albion After now applies that principle to its existing infected PvE without creating new fake damage, loot or PvP rules.

- Successfully restored **HP** adds 0.75 PvE threat per point, capped at 75 threat per medical action and infected.
- Party first aid, Expedition Triage Packs, and Restoration Staff pulses use the **same** server-owned rule.
- A zombie must already be engaged with the healed patient (current target or combat threat) and both healer and patient must remain within that infected's leash.
- Only real living party members in the same world zone can generate healer threat; safe hubs and unrelated encounters cannot.
- A multi-target heal is aggregated once per enemy. Curing infection, stopping bleeding, overhealing, failed actions, missing supplies and cooldown replays grant **zero** extra threat.
- Ordinary `Threat.pick()` switching margin, decay, Guardian taunt, pursuit limits and zombie death cleanup still apply. No private hate tables are replicated to clients.
- There is no new RPC or character-save field; the server derives values from actual health deltas.

Test suite: `game/tests/test_healing_aggro.gd` registered in `game/tests/run_all.gd`.
