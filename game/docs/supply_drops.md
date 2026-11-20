# Public PvP supply drops

The authoritative game server schedules a public loot cache after **600 seconds of active
server simulation**, with a retry every 60 seconds if no living player is in a dangerous
(red/black) zone or no dry, sufficiently flat landing spot is found. A site appears
32–54 m from an eligible survivor so their normal network interest radius includes it.

- Rewards use existing items: T3/T4 metal and cloth, silver, bandages, 9 mm ammunition.
- The item selection and site are determined solely by the server RNG; the client has no
  endpoint to create a cache or change its rewards.
- The server spawns up to three nearby infected guards. While one assigned guard
  remains alive, the cache is sealed. Guards remain active even if players retreat.
  If no guard can spawn safely, the crate is public immediately.
- Once cleared, caches are public (no party/raid reservation) under existing full-loot PvP rules.
- Orange `SUPPLY DROP - guarded (N)` models become blue `SUPPLY DROP - public` after the guards fall. Every connected player receives a coordinate/tier announcement; only nearby
  clients receive the visible loot bag snapshot. Contents remain server-side.
- They expire after **420 seconds** or disappear when looted. Partial looting respects
  inventory capacity and keeps uncollected items on the ground.
- Timers are in-memory world-session timers; this first iteration intentionally does
  not checkpoint caches across dedicated-server restarts.

Test registration: `game/tests/test_supply_drops.gd`, run with
`godot --headless --path game --script res://tests/run_all.gd`.
