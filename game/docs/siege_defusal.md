# Defending a PvP barricade: siege charge defusal

A defender can now craft a **tier-two Field Siege Defusal Kit** at a
workbench (1 bar T2, 4 scrap, 1 cloth T2, 1 fiber T2) and use it to
remove a hostile armed charge from a barricade.

Use the **Disarm siege charge** button in the inventory. It uses the
existing authenticated item-use RPC. A successful attempt consumes one
kit. The server selects the closest active charge within **3 m**, checks
the original still-live barricade and its authenticated owner, the
server-controlled four-second fuse, PvP zone, and first solid blocker.
The action is impossible through rocks, ruins or other walls.

Failures (wrong owner, distance, expired fuse, blocking geometry or
missing tool) do not consume supplies. Successfully removed explosives
cannot detonate again; late attempts cannot prevent a server-authorized
blast. Nearby survivors receive a small notification, while distant
players receive no base location or account identity.

Uses existing Godot GDScript crafting, inventory, barricade and
multiplayer systems; **no engine changes required**.

Regressions: `game/tests/test_siege_defusal.gd`, registered in
`game/tests/run_all.gd`.
