# Field party provisions

Party members can share basic survival supplies through the existing **Party → Aid / Share** action in the main online client. Select a teammate, choose a supply from the dropdown, and press **Aid / Share** while standing within 3.2 metres (and within 2.5 metres vertically).

- **Berries / canned food** restore the recipient's hunger using the item registry's normal food value.
- **Water bottle** restores thirst using the normal drink value.
- **Bandage, antiseptic, antibiotics and serum** retain their existing medical effects.

The action is authoritative: it requires two living members of the same party, proximity, a real item in the giver's inventory, and a recipient who actually needs that effect. Failed requests do not consume items or start a cooldown. A successful action consumes exactly one item and shares the same five-second cooldown as medical aid. Supplies never heal HP or cure infection, and special cooked meals cannot bypass their own consumption rules.

The existing private party-aid event goes only to the giver and recipient; the UI shows the **actual** hunger/thirst restored. No new RPC, save migration or engine APIs are needed.

Regression coverage: `res://tests/test_party_aid.gd`, already part of `res://tests/run_all.gd`. Run with:

```sh
godot --headless --path game --script res://tests/run_all.gd
```
