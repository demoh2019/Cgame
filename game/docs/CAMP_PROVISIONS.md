# Camp provisioning for party expeditions

In the **Party** panel choose one nearby teammate, then click **Give Food**,
**Give Water**, **Give Kit**, or **Give Stew**. The server transfers the
following physically owned items into their backpack, without automatically
eating/drinking: `food` = 1 Canned Food; `water` = 1 Water Bottle;
`kit` = 1 Canned Food and 1 Water Bottle; `stew` = 1 Camp Fish Stew.

Both survivors must be alive, in the same voluntary party, on foot, not
recalling or in combat, within **3.2m of each other** and beside the **same
active field campfire**. The gift shares the existing **5-second party-aid
cooldown**, preventing rapid alternation with bandages or food aid. Only
authenticated server peer IDs can send, and only the recipient and donor can
receive the associated private event.

No item IDs or quantities, campfire IDs, proximity, recipient inventory
or party membership are supplied by the client. Two cloned inventories are
validated and changed first, then both committed together. Insufficient
supplies or a full receiving backpack roll back the complete package.
Both player inventories and characters are marked for account persistence.
No temporary unsecured chest or expiring supply storage is introduced.
Godot engine modifications and new persistence fields are unnecessary.

Tests: `game/tests/test_camp_provisions.gd` registered in
`game/tests/run_all.gd`; run `godot --headless --path game --script
res://tests/run_all.gd`.
