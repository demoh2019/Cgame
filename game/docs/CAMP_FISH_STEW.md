# Camp fish stew: one cooked meal for hunger and thirst

**Camp Fish Stew** is a new Tier 1 recipe available in the existing crafting
catalog. It uses **1 Raw Fish + 1 Water Bottle + 1 Wood T1**, and produces
**1 Camp Fish Stew** at an active nearby field campfire or the safe-hub
workbench. It does not accept unsafe raw/murky lake water. The clean bottle
may come from a canteen refill, boiled pouch, rain collection or trading.

- **0** cooks the best affordable tiered fish as before.
- **Shift+0** cooks one stew if the server verifies the station and inputs.
- **1** eats canned food as before.
- **Shift+1** eats one carried stew (or use it directly in the inventory).

Eating stew restores **40 hunger and 38 thirst** before existing food-power
bonuses and 0..100 caps. It also refreshes the existing **T1 prepared-meal
stamina/combat-energy recovery** (120 seconds); it cannot stack another meal
bonus or create new persistence state. The same real item consumption can
award survival experience once, if the player was hungry or thirsty. Ordinary
food remains non-hydrating.

All crafting and use commands use existing authenticated server RPCs, item
definitions, inventory checks, skill progression and save format. The
transaction for ingredients/output is atomic, including full backpacks.
The client never specifies a fire identifier, meal output, healing amount,
water amount or buff duration.

Tests: `game/tests/test_camp_fish_stew.gd`; registered in
`game/tests/run_all.gd`. Run with:
`godot --headless --path game --script res://tests/run_all.gd`
