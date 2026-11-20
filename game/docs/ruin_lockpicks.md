# Sealed ruin compartments and lockpicks

Improvised Lockpick Kits are workbench-crafted consumables: 2 scrap, 1 T1 metal bar, and 2 T1 fiber.
They extend the existing Days-After-style scavenging and Albion-style risk tier loop without introducing
a new client-side inventory authority or a privileged command.

- Only actual unopened, reachable **red/black zone ruin crates** can use a lockpick.
- The server checks that the survivor carries one kit, consumes **exactly one**, and rolls
  bonus materials with its local seeded RNG: 2–4 scrap plus 1–2 T3/T4 bars.
- Black-zone compartments have a **25% chance** of one field antiseptic; no raid trophy,
  weapons, or PvP loot is generated.
- Normal crate rewards, scavenging XP, respawn timers, and anti-farming remain unchanged.
- If the inventory is full, overflow uses the existing party-reserved ground bag handling.
- Searching green/yellow crates does not consume a kit.
- The owner sees a confirmation through the existing server event feed.

Regression tests are included in `game/tests/test_scavenging.gd` and run through
`godot --headless --path game --script res://tests/run_all.gd`.
