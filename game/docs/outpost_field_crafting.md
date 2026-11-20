# Captured outpost field workbenches

Holding a red/black-zone outpost now grants a physical **field workbench**
where the defending party can refine wood, ore and fiber and make any recipe
whose station is the ordinary settlement workbench. This supports a
player-driven economy and makes guild territorial control valuable.

- A rough timber bench appears beside every outpost banner. Its visual
  presence does **not** grant access: a server-validated capture is required.
- The crafting character must be alive, within 6.5 m of the banner, and
  either in the owning party or an authenticated member of its verified
  homogeneous Nakama guild.
- The server rechecks active membership, unexpired ownership, distance,
  actual survival state and enemy presence before each batch. Any enemy
  inside the 12 m capture circle immediately locks the bench.
- Mixed or unverified guild groups cannot forge a clan identity. Losing
  the flag, expiry or disbanding the owner party revokes access immediately.
- Crafting uses existing `Crafting.craft` atomic inventory transactions,
  recipe requirements, tier progression, costs and normal skill rewards.
  Field benches do not grant free resources and do not bypass requirements.
- The settlement workbench and campfire recipes still work as before.
  No additional client RPC, saved field, or engine extension is required.

Regression: `game/tests/test_outpost_field_crafting.gd`, registered
in `game/tests/run_all.gd`.
