# Craftable siege blast brace (T2)

A PvP base owner can manufacture one **Siege Blast Brace T2** at a
workbench using 2 T2 metal bars, 3 T2 planks, 5 scrap and 1 T2 cloth.

Use the **Brace nearby owned wall** inventory action beside a real wall
within 3 m. The server selects the nearest existing barricade and checks
ownership, PvP zone and an unarmed target. A foreign wall, remote
construction site, existing brace or already-armed enemy charge cannot
be reinforced. One physical kit is consumed per successful preparation.

The brace lasts at most **180 seconds**, absorbs **55% of raw damage**
from the *next real siege charge*, and breaks instantly. It applies
before the barricade's existing tier-specific reduction. Melee, acid,
infected and normal ranged wall damage remain fully effective and do
not expend the shield. Defusing a bomb likewise does not use the brace.

All brace state is server-side, short-lived and **not saved as permanent
wall HP**. Expired, dismantled or destroyed walls lose the device.
Nearby survivors see shield time in barricade snapshots and local
notifications when a brace is installed or consumed. No extra loot,
silver, invulnerability, teleport or new client RPC is added.

Regression: `game/tests/test_siege_blast_brace.gd` in
`game/tests/run_all.gd`. No Godot engine patch required.
