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
* **`** (backtick) switches to the old full text readout (every number and timer) for debugging and for the many small status lines.

`ui_theme.gd` gives every window a parchment look (paper card in a dark wooden frame, dark ink, brown buttons, red for the
main action) and keeps text over the world light. Item icons: `item_icons.gd` (game-icons.net, CC BY 3.0).

## Layout (in the manner of classic online RPGs)

* **Unit frame** (top left): a round portrait (skill progress ring, level badge), a parchment name plate with notched ends,
  and thin red health and blue energy bars with their numbers in a dark frame; a green line shows stamina while it is spent.
* **Effects row** under the bars: round icons for food and water (red when low), debuffs (red rim: infection, bleeding,
  fracture, cold, in combat) and buffs (green rim: meal, oils, whetstone, plate, salves, filters, flare, warmth, shelter...),
  each with seconds, charges or percent and a tooltip.
* **"+"** under the portrait opens the **Community** window (Group, Guild, Friends); party members are listed under the "+".
  Guild: find by name and join, found a guild, members, leave. Friends: add by name, online status, pending requests.
  Guilds and friends need the online account (Nakama); offline play says so.
* **Menu buttons** (top right): inventory, workshop, skills, map, controls; each presses the window's own hotkey.
* **Ability buttons** (bottom centre), **minimap** (bottom right, round plaque), quest card under the left column.
* **Bag** (right): paper doll with Bag, Head, Cape / Weapon, Armor, Hands / Food, Feet, Potion / Mount, silver and load;
  backpack grid and stash. Double click or drag an item onto its socket (it lights up while dragging) to wear or assign it.
  Food and Potion are quick slots (click to use, right click to clear). Side buttons filter by category (All, Weapons,
  Gear, Supplies, Materials, Other); several can be on, All toggles every category.
* **Actions** (left, tabs Gear, Field, Trade, Combat) and the **Workshop** (left, recipe rows with the product tile and the
  ingredients' have/need; the same category side buttons).
* **Worn gear**: hood (head), cloak (cape), gloves (hands), boots (feet), four tiers each, crafted at a workbench; every
  worn piece adds protection on top of the body armor (80% at most). Hood, cloak and boots show on the character.
* **Building**: U opens build mode, a see-through wall at the aim point, green where it may stand and red (with the reason
  in the prompt) where not; the mouse wheel turns it in eighths, a click or U places it, right click or Esc cancels.
  Walls show their tier's model (plank fence, cobble fence, stone wall, tall stone wall) and darken as they are damaged.
  A wall stays kept while its owner comes within 15 m or repairs or upgrades it; left alone for 6 hours of world time it
  crumbles over 2 hours. Facing and upkeep are saved with the world.
* **Fishing**: T casts (rod in hand, line and bobber on the water); when the bobber dips ("BITE!"), T strikes for one more
  fish; too early or too late the fish slips (the cast still pays as an ordinary one).
* **Title screen**: the sign-in card is a hanging red banner with the title, the fields and a red PLAY SOLO button.

## Controls

F2 shows every control (the same keys work in the local and the online client): 1-8 quick uses (food, water, bandage, next weapon, armor,
antiseptic, antibiotics, heat pack), `.` stim, `/` scent salve, R or F lake water, T fishing, Z camp rest, N and V vendor, P contracts,
B stash, Q or E interact. Siege outposts are drawn in the world with their owner's colour, capture ring and a label.

## On the world (world_overlay.gd)

* **Health bars over the infected** instead of text: red, gold for elites, magenta for raid bosses, a red frame when they hunt you, STUN and PIN tags.
* **Damage numbers** pop up where a hit lands (yellow on the infected, red on you, orange on other players).
* **Place markers** at the screen edge for the three nearest places within 650 m: name (or "? Village" until you discover it), kind colour and distance.

## Inventory window

Two columns: the backpack (slot cards with a border in the tier colour, gold when equipped, kind tag, tooltip) and the protected stash on the left, every
action of the game in a scrolling list on the right; centred and always on screen. The log has a fixed width and wraps; the prompt pill hides when empty.
