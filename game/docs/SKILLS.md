# Skill tree (K in the online client)

Every kind of action trains its own skill. A skill levels from 1 to 50, every level gives a passive bonus **and one
skill point**, and points are spent on perks in the skill's branch. All of it is decided by the server and saved with
the character (Nakama), so a forged save or a modified client cannot give XP, levels, perks or bonuses.

| Branch | Skill | Trained by | Passive per level | Perks |
|---|---|---|---|---|
| Gathering | Woodcutting, Mining, Foraging | gathering their nodes (more for higher tiers) | +1.2% gather speed, +0.4-0.5% extra yield | faster gathering, extra yield, capstone |
| Combat | Melee, Marksman | hitting enemies (more for harder hits) | +0.8% damage, crit chance / ammo saving | damage, crit, ammo, capstones |
| Combat | Slayer | killing the infected | +0.6% damage to them, +1% silver from them | damage, bounty, capstone |
| Combat | Toughness | surviving damage (capped per hit) | 0.4% damage reduction, +0.6 max health | damage reduction, max health, capstone |
| Survival | Athletics | sprinting (1 XP per 6 m actually moved) | +0.3% move speed, -0.8% stamina cost | speed, stamina cost, regeneration |
| Survival | Survivalist | eating and drinking while hungry or thirsty | slower hunger and thirst, stronger food | slower hunger, thirst, nutrition |
| Survival | Medic | bandages and medicine that have an effect | +1% healing | healing, capstone |
| Craft | Crafting | crafting at the workbench | 0.4% chance to save a material | material saving, capstone |
| Craft | Scavenging | searching crates and bags | +1% silver, chance of an extra item | silver, extra items |
| Explorer | Explorer | distance travelled (1 XP per 25 m) and new regions | +0.8% carrying capacity, +0.2% XP | capacity, faster training for everything |

Rules that keep it honest: refused actions never give XP (too far, depleted node, missing materials, no ammo, no
stamina); eating or drinking while full teaches nothing; standing still teaches nothing; distance counts what the server
moved, not what the client claims; damage XP is capped per hit; a new region pays once. Bonuses have hard caps.

Perks need the skill level for each rank and sometimes a rank in an earlier perk (capstones need rank 3 of the first
perk and level 40). Points are shared between all skills, so a hunter can also invest in carrying capacity.

Numbers live in `scripts/shared/skills.gd`; the server hooks are in `scripts/server/game_server.gd` (`_award`,
`cmd_perk`, `_apply_skill_bonuses`). Tests: `tests/test_skills.gd` (curve, perks, bonuses, forged saves) and
`tests/test_skill_actions.gd` (every action on the real server), plus the `skills` bot in the end-to-end run.
