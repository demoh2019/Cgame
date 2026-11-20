# The interface

`scripts/client/hud_skin.gd` draws the heads-up display on top of the game; it only reads `client.you` and cannot change anything.

* **Vitals card** (top left): character level badge, weapon and kills, an animated health bar with a trailing "recent damage" bar and a
  heartbeat when low, stamina and combat energy, hunger and thirst (they turn red when low), and chips for infection, bleeding and cold.
* **Zone and clock** (top centre): zone name with its rule (PvE / PvP and full loot), game time, weather, temperature, "Sheltered".
* **Quest card** (under the minimap): the camp contract, the daily bounty and urgent alerts (PvP combat, self-defense, blood scent ...).
* **Action bar** (bottom): weapon (ammo count), active skill (G) with its energy cost, dodge (Space), drink (F, lit near water), use (E);
  cooldowns sweep clockwise with the time left.
* **XP strip**: the skill you trained last, its level and progress, fading after a few seconds.
* **Banner** for level ups and learned perks; the screen edges pulse red at low health and flash when you are hit.
* **Log**: translucent card, messages fade after 14 s. Interaction prompt as a pill above the action bar.
* **F3** switches to the old full text readout (every number and timer) for debugging and for the many small status lines.

`ui_theme.gd` styles the remaining windows (inventory, crafting, skills, chat).
