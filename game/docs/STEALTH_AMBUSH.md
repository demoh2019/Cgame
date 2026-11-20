# Silent PvE ambush

With a genuine equipped and carried melee weapon, hold **Ctrl** and approach
an unaware regular infected from behind. A normal attack at 2.4m or less
delivers **45% bonus damage** on the opening strike. Enemy orientation,
distance, posture and aggro are all computed by the authoritative server.

The opener requires silence and no bleeding. It does not work with fists,
firearms, active skills, already-engaged enemies, elites, bosses or guards of
public supply caches. Damage against players is unchanged. Crits and the
opening bonus do not stack. Ordinary combat rules handle the attack, loot,
death and XP; no reward is manufactured by the ambush feature.

The attacker receives a private "stealth_ambush" event and HUD feedback.
Both offline and online clients use the existing attack control (F offline,
normal melee attack online) while crouched. No engine modification needed.

Regression: res://tests/test_stealth_ambush.gd
godot --headless --path game --script res://tests/run_all.gd
