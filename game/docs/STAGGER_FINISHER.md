# Stagger finisher

A classless PvE melee counterattack that rewards parry, flash charge and
heavy-weapon crowd control. Press **Shift+G** (both online and offline) or
the **Finish staggered infected** inventory action. The server selects the
nearest staggered, living, non-boss infected in front of the player and within
the equipped weapon's actual melee reach. No enemy ID, hit result or damage
is accepted from the client. A real carried melee weapon is mandatory;
world/constructed blockers obstruct finishing hits.

A successful strike consumes **24 combat energy**, applies **1.7x weapon
base damage** with owned mastery and melee bonuses, and uses the ordinary
server-owned PvE damage/loot/XP pipeline. The stagger is consumed and any
surviving target receives a short 0.45s attack recovery. The skill also
applies a 0.65s attack lock and a separate 6s finisher cooldown.

No enemy in reach, inactive stun, obstructed angle, absent weapon, mount,
insufficient energy and cooldown are rejected **without payment**. Does not
damage other survivors, raid bosses, PvP duels, barriers or acid zones.
A failed attack cannot produce XP or loot; successful kills use the same
award path as ordinary melee. The owner-only event never leaks target
coordinates to unrelated peers. Temporary cooldown is not saved.

Test:
godot --headless --path game --script res://tests/run_all.gd
