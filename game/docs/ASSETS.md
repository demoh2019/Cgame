# Art assets

The game draws with two sets and prefers the first when it is present.

| Set | Where | In the repository | Used for |
|---|---|---|---|
| Downloaded packs | `assets/packs/` (made by `tools/import_downloads.sh`) | **no** | characters and zombies, nature, houses and props, animations |
| Kenney starter kits | `assets/kenney/` | yes (MIT code, CC0 assets) | fallback, fountain, sounds |

`tools/import_downloads.sh [dir]` copies the packs you downloaded (default `~/Downloads`) into `assets/packs/`:

* **Characters - Fantasy Races Kit** (Quaternius, QAL): Elf and Orc, male and female. Players pick one by their id; zombies are
  tinted orcs (walker, brute) and an elf (runner).
* **Universal Animation Library 1 and 2** (Quaternius, CC0): idle, walk, jog, sprint, punch, sword, pistol, tree chopping, harvesting,
  zombie idle, walk and scratch, death. They share the characters' 65-bone skeleton, so they play on any of them. Godot's glTF
  importer drops the `_Loop` suffix and loops those clips itself; `Assets.animation_library()` adds the `_Loop` names back.
* **Stylized Nature MegaKit** (Quaternius, QAL): trees, rocks, bushes, grass, ferns, flowers, mushrooms and pebbles. The first four
  are the gatherable nodes, the rest is client-only decoration scattered from the seed.
* **Slavic World Free as GLB** (EmacEArt): houses, walls, crates, barrels, benches, tables and baskets for the hub, the ruins, loot
  crates and bags.

Why they are not committed: the Quaternius Asset License and the EmacEArt licence allow using the assets in a game but forbid
redistributing the files themselves, and a public repository is exactly that. Everyone imports their own copy. Without the packs
(a fresh clone, CI) the game falls back to the Kenney set and all tests still run.

Houses are scaled so their longest side is 7 m, which matches the circle the server collides with (3.7 m radius).

## More packs (second import)

`tools/import_downloads.sh` also takes, when present in the downloads folder:

* **HighLandsFantasyBuildings** (FBX): huts, barracks, a town centre, towers, a wall, a windmill with turning sails and props. Only the diffuse
  atlases are used (shrunk to 2048 px, normal maps skipped: 70 MB each).
* **KayKit Dungeon Pack** (CC0, glTF): pillars, broken walls, rubble, stairs, chests, kegs, tables, torches, beds and shelves for ruined cities, bunkers and forts.
* **FreeVersion** (RAR, one textured glb): market stalls, huts, benches, braziers, lamps, logs, fences and stone walls.
* The loose **glb** files: a painted tree collection, a stone pack, crystals (used for ore), a treasure chest, logs, stumps, flowers, a mystic stone.

Most of these are collections of many objects in one file, each far from the origin and in its own units, so `scripts/client/model_catalog.gd` bakes
every object into its own mesh once: transform applied, scaled to a size in meters, bottom centre at the origin. The lists (`HOUSES`, `PROPS`, `RUINS`, `CRATES` ...)
are filtered to what is installed and a variant number from the world data picks `variant % installed`, so the server never loads a model and a missing pack
shortens a list instead of breaking anything. Blocking radii of props and ruins live in `WorldPoi` (`PROP_RADII`, `RUIN_RADII`); `tests/test_model_catalog.gd`
checks that both sides stay the same length.

Not used: the 163 MB floating island, the 57 MB apothecary lab, the forest scenes, the aloe set and the rock formations (each is one huge scene or in
centimetre units; they would need hand-made splitting), and the Wandering Merchant, Treasure and Throwing Animations packs.
