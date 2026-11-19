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
