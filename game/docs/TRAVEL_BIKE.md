# Salvaged Trail Bike — authoritative travel

This original post-apocalyptic travel feature combines wilderness exploration
and the crafted equipment economy of an MMORPG.

**Crafting:** Build one Salvaged Trail Bike (`salvage_bike`) at the T2
workbench using 4 metal bars T2, 3 planks T2, 5 scrap metal and 4 fiber T2.
It weighs 12 kg, occupies a real inventory slot, and can drop as loot.

**Controls:** F4 toggles riding in both the offline preview and network
client. Riding moves at 1.9× walk speed (7.98 m/s without bonuses), without
sprint stamina use. The server applies regular water, collision, encumbrance
and fracture limits. Crouching cancels riding. Gathering, looting, crafting,
consumables, melee/ranged attacks, weapon skills and dodge require dismounting.

**Combat rules:** The server rejects mounting during combat, when over-encumbered,
exhausted, injured or busy gathering. Real damage forces dismount and a 12s
remount cooldown; voluntary dismount starts a 2s cooldown. Trading or dropping
the bike immediately invalidates riding on the next server tick. Only the item
persists across sessions; riding state and cooldown do not.

**Networking:** Mount activation uses a reliable authenticated RPC.
Clients receive mount state via snapshots and use the same movement
prediction. Network movement packets never supply mount speed authority.

## Tests

`godot --headless --path game --script res://tests/run_all.gd`

`game/tests/test_mounts.gd` checks crafting data, speed bounds, server
ownership, combat restrictions, hit dismount, cooldown and save/load.
