# NPC caravan delivery routes

Players can now undertake **real inter-settlement courier contracts** at
procedurally generated village and fort workbenches. This connects
the world map, risky transport, harvesting and regional supply/demand.

- At a *non-hub NPC station*, click **Take route**. The server chooses
  the nearest qualifying other settlement **190-900 m** away and
  specifies a real import cargo (three T2 fish, ore, fiber, stone or wood).
- Gather or buy the goods, physically travel to the named destination
  and use **Deliver cargo** at its merchant workbench.
- The payout (50-140 silver, determined by distance and zone risk)
  requires all three actual cargo items. An atomic inventory transaction
  prevents partial loss or free silver if the backpack is full.
- Route initiation, destination and rewards are never client-specified.
  Network RPCs accept only **accept**, **deliver** or **abandon**.
- A route persists across account logouts using only four canonical
  source/destination identifiers; loaded saves are validated against
  deterministic world generation. Altered routes are rejected before
  affecting the live character.
- The private character HUD and server response show the cargo and
  destination coordinates. Completed trips grant Explorer XP and
  4 renown. An abandoned route has no reward or refund.
- The safe hub cannot generate inter-settlement missions, and remote
  villages still cannot access the protected account stash.
- The implementation reuses Godot's existing GDScript systems, NPC
  settlements, network layer and inventory: no engine patch required.

Regression: `game/tests/test_caravan_routes.gd` in
`game/tests/run_all.gd`.
