# Improvised flash charge: tactical crowd control

A crafting-funded survival tool for brief escapes from infected swarms.

- Craft `flash_charge` at a real workbench using 2 Scrap, 1 Metal Bar T2, 1 Cloth T1 and 1 Stone T1.
- Face outward in the dangerous wilderness and use **Throw flash charge**. The 8 m flight path is derived by the server and rejects blocked trajectories, invalid vectors, protected hub zones and water.
- A real impact interrupts up to **4** nearby living infected within **5.5 m** and not behind a solid world blocker. Regular infected are staggered for **1.25 s**, elites for half. Raid bosses and other players cannot be stunned.
- A **12 s** server-authored cooldown persists across reconnects and is strictly validated. The charge is consumed exactly once on success; failed casts (no targets, malformed direction, missing gear) cannot consume supplies.
- A successful flash produces **28 m** of attacker noise for **1.8 s**. Infected outside the immediate stun can hear the throw, so the tool is a tradeoff, not invisibility.

The game reuses zombie stagger, world blockers, crafting, combat noise and reliable multiplayer commands; the client supplies only a direction, not targets or hit results. No Godot engine patch is required.

Test: `game/tests/test_flash_charge.gd`, registered in `game/tests/run_all.gd`.
