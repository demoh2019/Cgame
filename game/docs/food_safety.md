# Field food safety: raw fish, cooking and stomach remedy

Food safety is part of the canonical `game/` world, not an isolated demo.
The same authoritative `GameServer.cmd_use` and `cmd_craft` powers the
networked client and the local preview.

## In-game loop

- Catch **Raw Fish** (T1-T4). Normally cook it at a live field campfire or
  settlement workbench into a **Cooked Fish** meal. The original recipes and
  profession tier requirements are unchanged. Properly cooked fish provides
  its usual hunger restoration and meal effects without new food poisoning.
- In an emergency when hunger is 85 or below, choose **Eat raw fish** from
  the Field actions in the inventory or press **Alt+1**. One real carried
  raw fish is consumed, restores a small amount of hunger (14-26), and
  inflicts food poisoning (32-50 severity, scaled by fish tier). Raw fish
  remains a regular resource for storage, trading and crafting.
- The **Food Poisoning** status appears beneath the portrait. Symptoms
  increase thirst drain and cause gradual health loss. They naturally
  recover over time; the effect is integrated by elapsed game time, not
  frame count, and is capped at 100.
- For faster treatment, craft **Herbal Stomach Remedy** anywhere from
  **2 wild herbs + 1 charcoal filter + 1 clean water bottle**. Use it
  from the inventory's Field actions or with **Shift+F11**. One dose
  reduces symptoms by 75 and is spent only if the survivor is poisoned.
  This is not a substitute for antibiotics against infected bites.
  The existing **Ctrl+3 quick medicine** can select this remedy for an
  actually poisoned survivor. A nearby party medic can also select it in
  Aid or use automatic Aid on a poisoned teammate, with the usual party,
  distance and cooldown restrictions. Neither path creates free medicine.

Other existing keys remain unchanged: **1** canned ration, **Shift+1**
camp fish stew, **F11** herbal poultice. Raw fish uses **Alt+1** instead
of replacing another food shortcut.

## Authoritative and persistent

- `scripts/shared/food_safety.gd`: accepted fish IDs, hunger benefits,
  severity levels and integrable damage/thirst coefficients.
- `scripts/shared/defs.gd`: unchanged fish identities marked as unsafe
  emergency food; craftable medicine registered as a real item.
- `scripts/shared/survival.gd`: illness added to the survival simulation,
  recovery, treatment, death reset and exposed vitals.
- `scripts/server/game_server.gd`: validates real item ownership, need,
  item debit and treatment; persists and strictly validates `food_poisoning`
  in account saves (missing field defaults to zero for older saves). Only the
  survivor's own snapshot shows symptoms. Changes are marked for autosave.
- `scripts/client/hud.gd`: debuff icon, clear gameplay actions and result
  feedback. `online_main.gd` and `client_main.gd` support the same
  fast keys.

Only authoritative server state controls symptoms, item costs and recovery.
The client cannot select arbitrary hunger, poison severity, or an unearned
cure. There are no new networking protocols or engine C++ requirements.

## Regression suite

```sh
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/smoke_client_scene.gd
```

`tests/test_food_safety.gd` checks catalog registration, legitimate
usage, poisoning caps, frame-independent damage, thirst, strict saved
state and legacy migration, crafting debit, no-effect protection, cured
symptoms, safe prepared meals and respawn reset.
