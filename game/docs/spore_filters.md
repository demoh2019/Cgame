# Expedition spore filters

A field-craftable consumable for the infected swamps. It gives a survival option
between unprotected scavenging and expensive tiered sealed suits.

- Craft **1 Expedition Spore Filter** in the field with 1 charcoal filter,
  2 T1 cloth and 1 field antiseptic. Materials are debited atomically.
- Use from the inventory or press **;** in either local or online play.
  One owned filter lasts **120 seconds**, consuming exactly one item.
- Reduces **ambient swamp spore infection** by 75%. It does not prevent zombie
  bite infection, acidic spitter attacks, other damage or PvP.
- Sealed-suit resistance combines multiplicatively with this consumable,
  capped at **95%** total protection. The remaining infection risk is intentional.
- The server owns the timer and samples the actual biome, gear and position.
  At timer boundaries, a long tick integrates covered and uncovered seconds
  separately. Neither the client nor a save can provide arbitrary protection.
- The remaining time is visible in the HUD and saved with the character. Invalid
  or nonfinite save fields are rejected before applying any state. Legacy v1
  characters load with zero remaining seconds. Death clears an active filter.

Run `godot --headless --path game --script res://tests/run_all.gd` for the
full regression suite, including `test_spore_filter.gd`.
