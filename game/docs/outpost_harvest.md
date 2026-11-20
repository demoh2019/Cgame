# Outpost harvest bonus

A captured red/black-zone outpost grants its owning party, plus other verified
Nakama guildmates of a homogeneous owning party, **one extra raw crafting
material** per completed resource node within a **100 m** radius.

- Applies to wood, ore, stone and fiber nodes; never berries, fish or crates.
- The server checks the outpost's still-valid owner, live party membership,
  verified guild affiliation, PvP zone and actual node/character position.
- A hostile player inside the outpost capture ring cancels the benefit immediately.
  The check is live at harvest completion, not a client snapshot or a stale
  `contested` flag. Contested sites can still be captured under normal rules.
- Only one bonus applies per node, even if outpost regions overlap.
- The inventory limit is respected. An `outpost_bonus` event indicates how
  many extra units were actually transferred (zero when a full bag prevents it).
- The bonus gives the normal resource experience for resources truly acquired;
  it does not bypass gathering tool requirements or depleted node cooldowns.
- Losing, expiring or disbanding the owning party ends the effect immediately.
- No new save-format field or engine module is required; the feature uses
  existing server-owned territory, guild identity, inventory and event channels.

Regression: `game/tests/test_outpost_harvest.gd`, registered in
`game/tests/run_all.gd`.
