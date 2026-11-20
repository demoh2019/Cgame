# Voluntary party recovery call

After a real red/black full-loot death, click **Ask party to recover
dropped gear** in the group controls. This is opt-in, not automatic.

The server derives the physical bag and caller identity from the live
world and account. No coordinates or bag IDs come from clients.
Members of the **current** group of 2-5 can see a pink radar arrow and
click **RECOVER TEAMMATE GEAR** on the atlas for at most 90 seconds,
never longer than the real bag's remaining life. Repeat requests are
group-rate-limited (18 seconds).

The signal is revoked when the author leaves/disconnects, members leave,
the bag expires or another survivor loots it. Other players never
receive account tokens, item details or the private marker. This
feature does not reserve loot, restore gear, make the courier immune,
or bypass PvP. It uses existing Godot RPG parties, authenticated RPC
and per-viewer snapshots; no engine modification is required.

Regression: `game/tests/test_party_corpse_rescue.gd` registered in
`game/tests/run_all.gd`.
