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
- Cross-training: three **distinct skill branches** with substantial confirmed actions
  (at least 5 base XP per action) inside 180 seconds raise the paid rest bonus
  by **20 percentage points**, up to **+95%** for novices. Repeated actions
  within one branch count once, with a 15-second refresh guard.
- Cross-training is **session-only** and cannot mint bonus XP without paid
  rested credit. Its current 0–3 branch progress appears in the private HUD.
- **Deep practice:** two different skills in the **same discipline** within
  180 seconds unlock another **+10 percentage points** for meaningful actions
  in that discipline. For example, training woodcutting and mining empowers
  later foraging. Repeating one skill does not count as two; the server ignores
  actions worth less than 5 base XP and refreshes each skill at most once
  every 15 seconds. It requires no RPCs or new save fields.
- Novice cross-training (+20 points) and deep practice (+10 points) can stack
  with the base +75% rate, but their combined bonus is **capped at +100%**.
  This still spends the same paid reserve; no passive XP is generated.
  The HUD shows the number of currently trained disciplines.
- Near the XP cap, the server consumes only the part of the reserve that
  actually increased character XP beyond the base action's award.

The server alone owns the bonus and debits it from a validated character
field `rested_xp_credit`. Older version-one saves default to zero. It is
included only in the owner's `you` snapshot, not other players' presence.
The HUDs display remaining credit; the existing **Z** rest action remains
unchanged and there are no new RPCs or engine changes.

The adaptive rate is chosen by the server using the skill's current level and
recently confirmed action history, not client-supplied claims. Cross-training and deep-practice progress do not persist between sessions
or change gathering/crafting profession mastery counters. Existing saves remain compatible, including credit up to
the previous 120-point limit; replenishment now uses a 240-point ceiling.

The effect applies to the central `GameServer._award` skill tree, not to
the separate gathering/crafting mastery counters, loot quantities or combat
damage. Verify with:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Regression: `res://tests/test_rested_training.gd`.
