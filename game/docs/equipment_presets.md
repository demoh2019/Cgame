# Safe-hub equipment presets

Classless combat lets a player switch roles quickly without creating or
duplicating weapons, armor or account inventory. At the hub workbench, the
inventory UI now has three independent **Save / Equip / Clear** gear presets.

- **Save** captures the player's currently equipped weapon and armor item IDs
  from their actual carried inventory. Nothing is withdrawn or reserved.
- **Equip** checks that **both** recorded items are still carried. Missing,
  lost, sold, banked or looted items reject the entire action; one missing
  armor piece cannot make a weapon switch succeed on its own.
- **Clear** forgets the slot without touching the backpack or equipped items.
  Empty recorded weapon/armor fields explicitly unequip that equipment slot.
- Only alive survivors at the *safe hub workbench* can use presets. Combat
  tags, active attacks, casting, gathering, recall and mounting forbid swapping.
  There is no client-provided item ID, equipment stat or bypassable RPC path.
- Weapon switches clear previous coatings, sharpening and parry; armor
  switches clear armor plating. No effects from the old set carry over.
- The three-slot bounded dictionary array is validated before a character
  loads, deep-copied to the account save, and shown only in the owner's
  snapshot. Old saves have three empty slots automatically.
- Players still need to bring all required equipment in their backpacks.
  A saved preset is a shortcut, not a protected stash, an offline auction,
  a new inventory or a way around full-loot zone deaths.

Implementation: `scripts/shared/equipment_presets.gd`,
`scripts/server/game_server.gd`, `scripts/shared/net.gd`, and the
normal inventory panel. Tests: `tests/test_equipment_presets.gd`,
registered in `tests/run_all.gd`.

No changes to Godot engine binaries or player-save version are required.
