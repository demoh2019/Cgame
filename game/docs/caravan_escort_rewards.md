# Earned caravan escort shares

Escort participation is now a complete server-side gameplay activity.
Instead of creating extra silver, successful guard payments are funded from
the NPC trade contract's **existing 50–140 silver delivery fare**.

- A guard must join the courier's legitimate party **near the dispatch
  station**, then *physically travel* with the actual cargo carrier through
  four sequential route checkpoints: departure, 30%, 60%, 80% of the
  source-to-destination line.
- The server counts **at least 80 metres of actual resolved guard movement**
  within **28 m** of the living, cargo-carrying courier. Standing idle in
  the group, joining at the destination, spoofing coordinates and remote
  party membership do not qualify.
- The escort must be present and alive near the destination station at
  turn-in. Only members of the same live party ID and route qualify.
  Leaving, being kicked or disconnecting clears earned progress.
- Up to four eligible escorts share **at most 20% of the original fare**,
  with the courier retaining the remainder. Rounding leaves any residual
  silver with the courier. There is **zero net silver creation** from
  escorting. Guards also earn 10 Explorer XP and 2 renown.
- The cargo is removed and every silver transfer is staged through
  temporary inventories. If the courier cannot hold their fare or an
  eligible guard has no room, the **entire delivery fails without any
  item loss or partial reward**.
- Escort progress is session-only. Reconnecting with an unfinished
  courier contract requires the team to make a new trip; no old peer ID
  or group privileges survive a disconnect. The mission itself remains
  persistently saved.
- The party HUD displays private escort milestones and co-travel distance;
  reward receipts are only sent to the paid guard.
- No new RPC or engine patch is needed. Existing party, movement, inventory,
  XP, renown, Nakama save and event systems provide the authority.

Regression: `game/tests/test_caravan_escort_rewards.gd`, registered in
`game/tests/run_all.gd`.
