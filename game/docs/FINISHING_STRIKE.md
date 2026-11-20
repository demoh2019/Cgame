# Ruin Daggers — execution specialist

Original classless melee gameplay for Albion After. Inspired by the tactical
decisions of sandbox and raid MMORPGs without copying third-party assets.

* Craft **Ruin Daggers T1–T4** at a workbench using two matching-tier metal
  bars, one plank, one cloth and one piece of scavenged scrap.
* Daggers use the existing melee equipment slot, quick 0.55-second standard
  swings, and persistent server-owned melee mastery. Base damage at tiers
  1–4 is 11 / 17 / 23 / 29.
* Equip a real dagger and press **G** for **Finishing Strike**. The ability
  costs **30 combat energy**, has **6.5-second cooldown**, **0.85-second**
  attack lock and a short front melee cone.
* The finisher's base damage is 1.4× weapon damage. Against a **living
  infected with 35% or less of maximum HP BEFORE the hit**, the strike is
  multiplied by **2.0×**. Elites receive only **1.5×** and raid bosses
  **1.2×** instead; healthy, dead or invalid targets get no bonus.
* PvP targets never receive the execution multiplier. The existing zone,
  party, guild, consensual duel and weapon ownership rules apply. A miss
  still pays energy, and only real server-confirmed hits award combat XP
  or loot credit.
* Successful executions emit a nearby `finishing_strike` visual event.
  Online clients render a red-pink hit burst; the acting player sees a
  short HUD notification. No client sends the enemy's health or damage.

The mechanic needs no new Cgame/Godot native primitives; it extends the
server's existing melee hit and damage path. Tests are in
`game/tests/test_daggers.gd`, registered in `game/tests/run_all.gd`.

```sh
godot --headless --path game --script res://tests/run_all.gd
```
