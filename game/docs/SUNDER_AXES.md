# Ruin Sunder Axes — short-lived PvE exposure

An equipment-based support/damage role for cooperative post-apocalyptic
MMORPG raids. No copyrighted game assets or direct third-party copying.

* Craft **Ruin Sunder Axe T1–T4** at a workbench from three tier-matched
  metal bars, one plank, two fiber and one piece of scavenged scrap.
  Base damage is 15 / 24 / 33 / 42. Basic attacks are slower than daggers.
* Equip the axe and press **G** for **Sundering Chop**, costing **34 energy**
  with a **9-second cooldown**, **1.05-second attack lock** and short
  melee range. The active strike deals 1.25 times normal weapon damage.
* On a confirmed melee hit, a **surviving infected** becomes **EXPOSED**
  for 4.5 seconds. The application hit itself gains no bonus.
  Follow-up PvE damage from survivors increases by 18% against ordinary
  infected, 10% against elites and just 6% against raid bosses.
* Repeated applications refresh, never stack the multiplier or duration.
  Duration is based on the authoritative world clock, so off-screen AI
  sleep cannot artificially extend it. Dead enemies lose their status.
* **Players are never marked or given this PvE multiplier**. Existing
  PvP safety zones, guild/party protection, damage math, mastery and
  weapon ownership controls remain in effect. Misses do not apply a debuff.
* Server snapshots include only the remaining exposure duration.
  Nearby clients see an orange-tinted infected, a SUNDER health-bar
  indicator and a brief impact burst. Remote clients do not receive
  the world effect.

The mechanic extends existing shared inventory, movement and combat;
no native engine changes are needed for deterministic status effects.

Regression: game/tests/test_sunder_axes.gd, registered in run_all.gd.
Run with a compatible Godot executable:

    godot --headless --path game --script res://tests/run_all.gd
