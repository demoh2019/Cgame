# Three playable solo survivors

The game title screen now offers **Survivor 1**, **Survivor 2** and **Survivor 3** above the existing **Play solo** button.

- Each survivor has independent real `GameServer` world state, inventory, survival, skills, protected bank and account-owned structures. One server instance per slot runs on loopback ports **24566–24568**, and only one connection is accepted in each. One client can never inadvertently connect to another slot's process.
- Slot 1 preserves existing `user://albion_after_solo_character.json`, `user://solo_world.json` and `user://albion_after_solo_stop.signal` files; existing local players keep their progress.
- Slots 2 and 3 use suffixed character and world paths (`..._2.json`, `..._3.json`) and their own graceful-stop signals. Their saves are always local, even when Nakama happens to be running on the machine.
- As before, Slot 1 automatically uses the Nakama account when a local backend accepts connections; otherwise it uses its local character save. **Local saves do not automatically transfer to Nakama accounts.**
- A title-screen hint shows whether the slot has an existing *offline* character file. It does not parse untrusted inventory or declare corrupt saves playable: the server still validates the full versioned, seed-scoped character and fails closed.
- The real dedicated game server still owns every action, inventory transaction and save. The selection only changes the launcher parameters, not gameplay authority, external RPCs or network command semantics. The remote **Join server** button is unchanged.

Regression: `game/tests/test_solo_slots.gd`, included in the main `game/tests/run_all.gd`. This tests old-save backward compatibility, path and port isolation, offline/account routing and rejected slot indices.
