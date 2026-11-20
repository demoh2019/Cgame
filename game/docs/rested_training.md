# Rested training — paid shelter and classless MMO progression

Taking a **real rest** near the safe-hub workbench (or a lit field campfire)
also grants extra training credit, on top of existing paid health/stamina recovery.
This is not idle or offline XP: a survivor must spend real resources to rest and
then earn skill XP through actual gameplay.

- Hub rest: **30** points of bonus skill XP credit.
- Field campfire rest: **15** points.
- Maximum reserve: **120** points.
- Any successful server-awarded skill action can spend credit to earn **25%**
  extra skill experience, rounded to an integer and limited by the reserve.
- No credit is earned for rejected rests, full vitals, absent rations, unsafe
  campfires, or when the existing **90-second cooldown** is still active.
- No credit is spent on zero-XP, invalid-skill or maximum-level awards.

The server alone owns the bonus and debits it from a validated character
field `rested_xp_credit`. Older version-one saves default to zero. It is
included only in the owner's `you` snapshot, not other players' presence.
The HUDs display remaining credit; the existing **Z** rest action remains
unchanged and there are no new RPCs or engine changes.

The effect applies to the central `GameServer._award` skill tree, not to
the separate gathering/crafting mastery counters, loot quantities or combat
damage. Verify with:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Regression: `res://tests/test_rested_training.gd`.
