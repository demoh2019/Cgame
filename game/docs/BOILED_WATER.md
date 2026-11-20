# Boiled lake water — shared survival loop

At a **natural lake shoreline**, an equipped/carrying **Reusable Field Canteen**
can produce a clean **Water Bottle** in either of two ways:

- **Ctrl+R:** expend **1 Field Water Filter** (charcoal) to fill the canteen.
- **Ctrl+Shift+R:** expend **2 Wood T1** while standing within **3.2 m of a
  currently burning campfire**, at roughly the same elevation, to boil water.

These actions work in the online client and the local preview scene. The
canteen is reusable and stays in the player's backpack; nothing is created
if the bottle cannot fit. Expired fires, distant fires, missing fuel, absent
shoreline and dead survivors are rejected without inventory loss.

The fire may be lit by a teammate. There is **no client-provided fire ID**,
position, bottle quantity or chosen input cost: `GameServer` checks its own
campfire registry and shoreline terrain, and `FieldCanteen` makes an atomic
two-step inventory debit/credit. Either method triggers the **same existing
12-second lake-drinking/refill cooldown**, which is saved with the character
and prevents alternating or reconnect spam. Wild lake drinking still has its
normal infection risk unless filtered.

This also makes fires tactically valuable: finding wood, pitching a safe
lakeside campfire and guarding it during the night provides an alternative to
crafting charcoal filters, while a storm can extinguish the fire.
