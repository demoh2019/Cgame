# Camp Sentry Alarm — paid temporary infected warning

Craft a **Camp Sentry Alarm Kit** in the field from **1 Wood T1,
2 Fiber T1 and 2 Scrap**. Stand within **3.2m** of an active field campfire
with at least **45 seconds** of fuel, then use **Shift+O** or the
**Arm camp sentry alarm** button under Inventory -> Field.

The kit is spent only after the server validates an active nearby fire,
combat/recall state, sufficient burn time and lack of an already active alarm.
It lasts up to **180 seconds**, or less if the campfire runs out of fuel.
The server scans for living infected within **21m** every **2 seconds**, and
limits warnings to one every **24 seconds** per fire. Alerts report at most
five infected and never send target identities or exact enemy positions.

Alarm messages are shown to the installer and their **current party members
who are within interest distance (90m) of the fire**. Permission is checked
at delivery time; leaving the party, dying, disconnecting or moving away
removes access. No outsider can read a private alert. No PvP enemy tracking,
automatic damage, protection, infinite safe zone or permanent camp structure
is added. Sentries stop if the fire is extinguished or the installer
disconnects; they are never included in persistent world checkpoints.

Implementation: `scripts/shared/camp_alarm.gd`, `GameServer.cmd_arm_camp_alarm`,
`Net.c_arm_camp_alarm`, client controls, and `test_camp_alarm.gd` registered
in `tests/run_all.gd`. Run with
`godot --headless --path game --script res://tests/run_all.gd`.
