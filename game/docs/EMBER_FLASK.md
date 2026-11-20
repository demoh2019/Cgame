# Scavenged Ember Flask — PvE burning ground

Craft an Ember Flask at a workbench from 1 tier-2 metal bar, 2 cloth,
3 wood and 1 scavenged scrap. Press **F5** to throw a flask in the current
aim direction, about eight metres away. The server validates the path,
water, safe zones and terrain. Failed requests do not consume an item.

A successful throw creates six seconds of burning ground in a three-metre
radius. Fire deals eight damage per second to up to four infected. Raid
bosses take half burn damage. Flames never hurt players, never grant PvP
rights, and cannot burn through solid cover or high floors. A per-infected
global one-second throttle prevents stacking overlapping areas for extra
damage. Sixteen live hazards globally and two per survivor bound server work.

Tactical flasks share the existing **12-second persistent flash-charge
cooldown**, preventing cross-consumable and reconnect spam. A throw alerts
nearby infected within 19 metres for 1.5 seconds. Damage/kill/loot credit
reuse the existing authoritative zombie combat system. Flames disappear
when their owner dies, disconnects or retreats to a safe hub.

Hazards are session-only and never stored in character/world saves.
Nearby clients receive only the validated position, radius and remaining
time, and render orange ground-fire markers. Online and local previews
use the same authoritative game logic. Native engine changes are not needed.

Regression suite: `game/tests/test_ember_flask.gd` (in `run_all.gd`).

```sh
godot --headless --path game --script res://tests/run_all.gd
```
