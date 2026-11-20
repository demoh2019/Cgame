# Woven Trail Backpack T2

A new *full-loot*, craftable and tradeable expedition backpack gives miners,
scavengers, explorers and couriers a choice between travel capacity and risk.

- Craft from **4 cloth T2, 4 fiber T2, 1 plank T2, 2 scrap** at a real
  workbench, respecting the existing crafting mastery requirements.
- Physical weight **2.5 kg**, stack size **1** and no new inventory slots.
  The actual weight of all items, including the pack, is unchanged.
- Owning a pack provides **14 kg of ergonomic support while on foot**.
  This reduces the encumbrance speed penalty and can restore sprint when
  under the effective comfort threshold. Extra packs cannot stack support.
- **No bike double-dip**: while mounted, trail-pack support switches off.
  Only authentic, mounted bicycle panniers can provide their usual 28 kg.
  Server movement, client prediction, dodging and the inventory calculation
  share the same result.
- Selling, dropping, banking or losing the physical item removes support
  immediately. In red/black PvP zones the pack drops in the ordinary public
  death bag. It is never protected or automatically returned.
- HUD and offline diagnostics display active support. Saves and normal
  inventory replication already preserve ownership: no separate RPC,
  entitlement or engine extension is necessary.

Regression suite: `game/tests/test_trail_backpack.gd`.
