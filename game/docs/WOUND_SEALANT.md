# Antiseptic Wound Sealant

A field-crafted, single-use prophylactic dressing: combine **2 wild herbs**,
**1 field antiseptic**, and **1 cloth T1**. The normal inventory-use action
consumes one carried dose outside combat and grants **90 seconds** of bite
protection. Stacking/refreshing is denied without spending a second item.

Only infection from **physical zombie melee attacks** is reduced by **45%**.
Damage, bleeding, fractures, acid, airborne spores and PvP are unaffected.
The server applies the reduction after equipped-armor and party-ward effects.

Character saves validate the remaining buff, older saves start at zero,
death cancels the effect, and the private snapshot drives the HUD status.
All actions use existing authenticated networking and item/crafting systems.

Regression suite: `res://tests/test_wound_sealant.gd`, wired into
`res://tests/run_all.gd`.

Headless test: `godot --headless --path game --script res://tests/run_all.gd`.
