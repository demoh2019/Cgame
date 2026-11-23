# Rested training — paid shelter and classless MMO progression

Taking a **real rest** near the safe-hub workbench (or a lit field campfire)
also grants extra training credit, on top of existing paid health/stamina recovery.
This is not idle or offline XP: a survivor must spend real resources to rest and
then earn skill XP through actual gameplay.

- Hub rest: **60** points of bonus skill XP credit.
- Field campfire rest: **30** points.
- Maximum reserve: **240** points.
- A successful server-awarded skill action spends credit at a skill-level-dependent rate:
  **+75% XP** for levels 1–9, **+60% XP** for levels 10–24, and **+50% XP** for levels 25–50.
  Bonus XP is rounded to an integer and never exceeds the saved reserve.
- No credit is earned for rejected rests, full vitals, absent rations, unsafe
  campfires, or when the existing **90-second cooldown** is still active.
- No credit is spent on zero-XP, invalid-skill or maximum-level awards.

The server alone owns the bonus and debits it from a validated character
field `rested_xp_credit`. Older version-one saves default to zero. It is
included only in the owner's `you` snapshot, not other players' presence.
The HUDs display remaining credit; the existing **Z** rest action remains
unchanged and there are no new RPCs or engine changes.

The adaptive rate is chosen by the server using the skill's current level, not a
client-supplied claim. Existing saves remain compatible, including credit up to
the previous 120-point limit; replenishment now uses a 240-point ceiling.

The effect applies to the central `GameServer._award` skill tree, not to
the separate gathering/crafting mastery counters, loot quantities or combat
damage. Verify with:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Regression: `res://tests/test_rested_training.gd`.
