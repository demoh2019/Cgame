# Antiseptic Edge Oil

A craftable consumable that links swamp scavenging to Albion-style
preparation and Lineage-style monster hunting. Craft one **Antiseptic Edge
Oil** at a workbench from one **spore culture**, one **field antiseptic**
and one **scrap** (tier 2). Apply it with **Shift+6** or the inventory button
while a *physically carried and equipped melee weapon* is selected.

For 120 seconds that exact equipped weapon type gains **+20% damage
against ordinary or elite infected only**. Existing mastery, party focus,
stealth and relic traits continue working normally. No boost applies to
PvP, duels, raid bosses, barricades or environmental objects.

The server alone decides the weapon, consumption, time and damage factor.
Reusing the consumable while the effect is active, having no owned melee
weapon, or using ranged equipment does not consume an item. Changing
weapon, dropping it, death, logout or effect expiry clears the buff. No
client request controls bonus damage, duration, weapon or target.
Replicate buff duration only to the owner.

Run regression checks with:
godot --headless --path game --script res://tests/run_all.gd
