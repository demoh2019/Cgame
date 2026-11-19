# Days After — scavenging regression

The first game-level regression covers the existing `player.gd` and `pickup.gd`
without requiring a finished map or an editor session.

Run with the Cgame engine executable:

```sh
./bin/godot.linuxbsd.editor.x86_64 --headless --path demo/days_after --script res://smoke_test_inventory.gd
```

Replace the executable path for your platform or build name.

The test checks the starting health, the camera/aim hierarchy, single-use
resource transfers, food and water consumption, stat caps, empty inventories,
unsupported item types, and invalid negative quantities. It prints `PASS`
on success and exits nonzero if a check fails.

## Engine/game boundary

Keep rules about hunger, thirst, food, loot, crafting, quests, and zombies in
the **Days After project**. Add functionality to **Cgame** only when it is a
general engine capability that cannot be implemented soundly through existing
Godot nodes or scripting APIs. When extending Cgame, add an engine regression
test and an in-game use case together.

Future integration tests should load `main.tscn` when `main.gd` and the
playable world are present, including headless verification of the world and
zombie encounters.
