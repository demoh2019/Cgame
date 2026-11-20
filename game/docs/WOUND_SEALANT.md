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

## Team expedition preparation

Medics can select **Antiseptic Wound Sealant** in the ordinary **Aid / Share**
party action and apply one carried dose to a **living consenting party member**
within 3.2 metres. This shares the existing 5-second party-aid cooldown.
Both players must be out of combat and dismounted, including active server-observed
infected pursuits within the combat-pressure radius. A protected teammate cannot
receive a second dose until their current 90-second protection expires.
Failed attempts never spend medicine. The action uses the existing
authenticated party RPC, private medical events and the recipient's own
validated save/snapshot; there is no client-set duration or target immunity.

The hub expedition restock presets now include **1 sealant for scouts** and
**2 for medics**, withdrawn only from real protected-bank stock.

Regression suite: `res://tests/test_wound_sealant.gd`, wired into
`res://tests/run_all.gd`.

Headless test: `godot --headless --path game --script res://tests/run_all.gd`.
