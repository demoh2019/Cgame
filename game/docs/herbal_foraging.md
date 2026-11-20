# Wild herbal medicine and field poultices

An original survival-and-economy loop connecting wilderness foraging to
craftable medical supplies. No extra engine primitives or server RPCs are
required: it uses the existing world nodes, player inventory, crafting,
medical item use, skills, and authoritative multiplayer replication.

## Gathering

Genuinely depleted **bush** and **berry** nodes may produce **one Wild
Medicinal Herb** in addition to their ordinary fiber or berries:

- Forests: 24% chance
- Swamps: 42% chance
- Only danger zones 1–3, never the starter safe zone
- No extra herb if the primary harvest does not fit in the inventory

The server computes the node's biome, zone, and random roll. A second
request for an already depleted node cannot produce additional medicine,
and players cannot transmit a claimed harvest, drop count, or location.

## Medicine

Craft a **Field Herbal Poultice** anywhere from **2 wild herbs,
1 T1 cloth and 1 clean water bottle**. It heals 10 HP, reduces infection
by 18, and stops bleeding. The recipe costs real materials and produces
one stackable, tradeable item. It is weaker than rare antidotes, so danger
and high-level crafting remain valuable.

Use it via inventory in multiplayer or press **F11** in local and online
play. Healing, server ownership, save validation and inventory consumption
use the same logic as existing medical items.

## Test

`godot --headless --path game --script res://tests/run_all.gd`

The `test_herbal_foraging.gd` suite covers eligible biomes, dangerous
zones, deterministic rewards, replay prevention, material-paid crafting,
character persistence, and bounded medical effects.
