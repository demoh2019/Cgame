# Caravan ambushes in full-loot territory

Resource transport now creates real limited PvE combat pressure instead of
only a buy-and-sell checklist. This uses *existing server-owned infected AI*.

- While undertaking a village-to-village route, carrying at least **one
  actual contracted resource**, and having travelled at least **35% of the
  route** (minimum 80 m), a player can trigger a 2–4-infected ambush in
  a **red or black full-loot zone**. Attacks do not trigger at safe
  workbenches or immediately on top of the delivery destination.
- Zombie positions are selected with the existing `NightHorde.sites`
  terrain and player-proximity validation; water, steep terrain,
  barricades, spawn overlaps and excessive global AI load are avoided.
- The event is **once per active contract** and is recorded in the
  persisted character as `caravan_ambushed: bool`. Rejoining during
  an unfinished route cannot reset it. Abandoning or completing the
  route resets the marker for a future contract.
- A maximum of four simultaneous waves and 85 active total infected
  are allowed; waves despawn after 190 seconds. Normal infected
  combat and loot apply; **no new bonus silver, horde trophy or
  artificial free loot** is introduced by the event itself.
- A courier receives a private HUD warning, without disclosing their
  route or account to other players. Server RPCs accept no ambush
  arguments, positions, wave composition or rewards.
- Existing open-world PvP, caravans, party escorts, world roads,
  equipment, bike travel and loot restrictions remain intact.
- Engine changes aren't required: this is fully server-side GDScript
  plus a HUD event and deterministic regression tests.

Regression: `game/tests/test_caravan_ambush.gd` registered in
`game/tests/run_all.gd`.
