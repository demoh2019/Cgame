# Timed melee parry

A skill-based alternative to dodge: equip an owned melee weapon and press
**F8** (online or offline) or **Parry incoming infected (F8)** in inventory.

The server charges **20 stamina** and grants a **0.45-second** one-hit
blocking window, followed by a **4-second cooldown**. Incoming, close,
front-facing infected **melee** deals **30%** of its usual damage and
secondary bleeding/infection/fracture severity. The attacker is staggered
for one second. The bonus is consumed on the first valid hit.

A strike from the back, unarmed/gun-armed survivor, stolen weapon, mount,
insufficient stamina, attack lock, dodge overlap or expired window
cannot parry. Bosses cannot be parried. Parry does **not** affect PvP,
acid spitter projectiles/pools or area-of-effect raid slams; other attacks
continue using the usual damage and ward rules. Parry is not a PvP-safe
zone, heal, damage source or XP farm.

Only the actual server attack result checks facing and equipment.
The client sends no enemy ID or damage. The private `parried` event
notifies only the defender. The owner snapshot includes remaining window
and cooldown; these do not persist in character/world saves.

Regression suite:
godot --headless --path game --script res://tests/run_all.gd
