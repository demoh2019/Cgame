# Medic mastery for cooperative survival

The classless **Medic** skill and its **Field Medic / Triage** perks now matter
in team play: real acquired `heal_power` raises the health healed by manual and
automatic party first aid, and by crafted field triage packs. Healing threat
still uses **actual** restored HP and existing infected engagement rules.

To preserve PvP/raid balance, ally-health restoration uses at most **+35%**
from Medic mastery, even if the self-healing perk is stronger. All other
medicine effects (bleeding, infection, fracture, poisoning), targeting,
party membership, altitude, distance and cooldown are unchanged. Only
already-carried medicine or packs can be spent; no new currency is minted.

Actual HP restored and actual ailments treated award capped Medic XP after
the inventory debit. Empty or tiny heals, failed RPCs, replays and sharing
plain food/water grant no Medic XP. A full multi-target triage remains limited
to 5 XP per action. This uses the existing skills/save/XP events pipeline and
does not add new character-save fields or network commands.

Regression suite: `res://tests/test_party_medic_mastery.gd`.
Run it with all other tests:

`godot --headless --path game --script res://tests/run_all.gd`
