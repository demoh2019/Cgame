# Days After × Albion: equipment durability & repair

The playable survival prototype now has a lightweight durability loop for
crafted tools, weapons and armor. Durability is **per item type** in the
current single-player inventory, not per independent physical item instance.
Multiple copies of the same item share a condition value; this prototype
limitation should be replaced with unique item instances before trading.

## Gameplay

- **Scavenger tool** loses 3 durability per successful gather. At zero it
  cannot harvest T2 resources until repaired.
- **Spears** lose 2 durability per melee attack. A broken spear deals only
  unarmed damage and does not qualify as effective equipment.
- **Scrap vest** loses durability when protecting against damage. It mitigates
  the final protected hit, then provides no reduction after breaking.
- Items are not deleted on break; they remain repairable in inventory.

Repairs are atomic and cost:
- Scavenger tool: 1× wood T1 + 1× stone T1
- Rusty spear: 1× wood T1 + 1× stone T1
- Reinforced spear: 1× wood T2 + 1× stone T2
- Scrap vest: 2× fiber T1 + 1× stone T1

**F6** repairs equipped tool, **F7** equipped weapon and **F8** equipped
armor. Failed repairs never remove materials. Repairing a fully healthy item
is not allowed, and crafting another item of the same type does not repair an
existing damaged stack.

Durability is saved along with the survivor (F5/F9), and old version-1
saves without durability are accepted as fully repaired. The save loader
validates every condition value before changing player state.

## Test

```sh
<cgame-editor> --headless --path demo/days_after --script res://smoke_test_durability.gd
```

Tests cover breakage, tool-gated gathering, exact atomic repair costs, armor
damage reduction, snapshot persistence, corruption rejection and legacy saves.

No new Cgame engine API is needed: these are gameplay rules using existing
GDScript and serialization facilities. Multiplayer will need
server-authoritative equipment instances and transactional material costs.
