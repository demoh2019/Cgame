# Protected-bank expedition resupply

At the **hub workbench**, open **Inventory** and select **Scout**,
**Archer**, **Gunner** or **Medic** in the protected stash's RESTOCK KIT
control. Withdraws **only missing supplies** from already owned stash.

| Profile | Targets in backpack |
| --- | --- |
| Scout | Water 3, canned food 3, bandages 4, antiseptic 1, splint 1 |
| Archer | Water 2, canned food 2, bandages 3, arrows 48, poultices 2 |
| Gunner | Water 2, canned food 2, bandages 3, 9mm ammo 48, antiseptic 1 |
| Medic | Water 3, canned food 2, bandages 6, antiseptic 3, antibiotics 2, triage pack 1 |

This is not a shop or crafting shortcut. The server takes only real stock
from the character's protected bank. Already-carried supplies count toward
each target; surplus is never removed. Repeated clicks cannot exceed the
profile targets. Unavailable supplies and full backpack slots are skipped;
successful partial withdrawal is reported. A completely blocked transfer
changes neither container.

Authority: server-owned preset targets, authenticated RPC sender, current
hub workbench proximity, two staged inventories committed together, and
existing private save/snapshot mechanics. No new Godot engine feature.

Regression tests: `game/tests/test_expedition_loadout.gd` in the headless
`game/tests/run_all.gd` suite.
