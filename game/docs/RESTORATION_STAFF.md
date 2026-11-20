# Expedition Restoration Staff — classless party healing

The canonical `game/` now has an original equipment-based support role
inspired by cooperative RPG play. It is not a fixed class, and it does not
copy any third-party character, icon or asset.

* Forge a **Restoration Staff T1–T4** at the safe-hub workbench using two
  tier-matched planks, two cloth, one bar, and one field antiseptic.
* Equip the crafted staff through the existing weapon controls (key **4**
  cycles owned weapons in the local preview).
* Press **G** to use **Restoration Pulse**. In an online party of at least
  two members it heals **up to two injured teammates** within 8 metres
  horizontally and 2.5 metres vertically, prioritizing the greatest health
  deficit. Tier 1–4 heal **12, 16, 20, 24 HP per teammate**.
* The skill costs **40 combat energy**, with a **12-second cooldown** and
  a **0.9-second attack lock**. The caster does not heal themself.
  Players outside the current party, across zone boundaries, dead characters,
  and full-health teammates cannot benefit.
* Invalid or no-effect requests spend nothing and do not start the cooldown.
  Medical healing does not grant repeatable XP. The client supplies only a
  normal validated facing direction; the authoritative server decides
  recipients, effects and costs.
* The local single-player preview has no other party members, so it can
  craft and equip the weapon but **cannot demonstrate its healing ability**
  without the multiplayer party connection.

No new engine primitives or network RPCs were required: the existing
weapon ability command, world zones, party roster, combat energy, and
survival healing APIs already provide the necessary integration.

Headless regression suite:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

The dedicated regression file is `game/tests/test_restoration_staff.gd`.
