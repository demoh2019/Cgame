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

## In the repository: Poly Haven (CC0)

Poly Haven assets are public domain, so they are committed and every clone gets them:

* `assets/textures/terrain/`: eleven ground materials (grass, dry grass, forest floor, mud, dirt, cliff, mountain rock, sand, snow,
  cracked asphalt under ruined cities, broken concrete under bunkers, depots and docks), drawn by `assets/shaders/ground.gdshader`.
* `assets/textures/plaza/`: the hub's cobblestones (and the stone of its fountain). `assets/textures/sky/`: the day sky panorama.
* `assets/models/polyhaven/`: 42 scanned models: rocks, stumps and fallen trunks for the wilds; fuel and oil barrels, a fire barrel,
  jerrycans, military crates, ammo boxes, tyres, wheel rims, road barriers, bins, rubbish bags, propane tanks, a generator, street
  lamps, hydrants, tables, benches, racks and carts for ruins, depots, forts and villages (`PROPS` 26-49 in `model_catalog.gd`).
  `tools/fetch_polyhaven.sh` downloads the sources, `tools/bake_polyhaven.gd` cuts them to a triangle budget into `baked/*.res`;
  only the textures and the baked meshes are committed.

## Clothed survivors (third import)

`tools/import_downloads.sh` also takes **Universal Base Characters** and **Modular Character Outfits - Fantasy** (Quaternius, CC0,
free "Standard" versions from quaternius.itch.io). They share the animation library's skeleton. When installed, players, settlers and
infected walkers are people in clothes instead of the bare fantasy bodies: `character_model.gd` keeps only the head of the base body
(so skin never pokes through), adds an outfit (peasant, ranger or a mix of their pieces) and a hairstyle in one of six hair colours,
picked from the entity id. The infected get filthy peasant clothes and green skin; the brute stays the big orc. Each look is assembled
once and copied after that (about 1.5 ms a character), so a horde streams in without a hitch. The import shrinks the kit's 4096 px
textures to 1024 px (normal maps 512 px): at full size, loading them mid-game stalled the client long enough to be disconnected.

**Fantasy RPG Music Vol. 2** (its licence allows use in games, not redistribution) goes to `assets/packs/music/`: `audio.gd`
crossfades calm tracks by day, night tracks after dusk and action tracks for nine seconds after you hit or are hit.

## Weapons in hand (in the repository, CC0)

`assets/models/kaykit_weapons/`: thirteen models from **KayKit Fantasy Weapons Bits** (Kay Lousberg, CC0). `character_model.gd`
hangs the equipped weapon on the right hand bone (`BoneAttachment3D` on `hand_r`), for you, other players and armed settlement
guards; the axe shows while chopping. `HELD_MODELS` maps weapon families to models (club, spear, machete, sunder axe, dagger,
sledgehammer, restoration staff, bow, crossbow, purifier maul, axe; the pistols use the Kenney blaster) and `HELD_SCALES` sizes
them, since the kit is about twice life size. Melee swings leave a short streak (the engine's `Trail3D`).

## Interface icons (in the repository, CC BY 3.0)

`assets/icons/items/` (one silhouette per item, shared by its tiers) and `assets/icons/ui/` (menu buttons, action bar,
portrait, food and water) come from **game-icons.net** by Lorc, Delapouite, Skoll, Sbed, Carl Olsen, Darkzaitzev,
Faithtoken and John Colburn, licensed CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/). The dark background square
of each SVG was removed so the interface can tint the white shape; nothing else was changed. `item_icons.gd` picks the icon
for an item and its tint by item kind.

## Engine features the game uses

* **Camera3D trauma shake** (this fork): hits on you, your blows, nearby deaths, flashes and smashed barricades.
* **AudioStreamInteractive**: the day, night and combat music is one adaptive stream that crossfades between its clips.
* **Trail3D** (this fork): swing streaks on melee weapons.
* **EnvironmentQuery3D** (this fork, on the server): a chasing pack spreads around its prey instead of queueing behind one
  another (`zombie.gd` `_flank_goal`).
* Animations of the Universal Animation Library now also used: crouching, riding, swimming in deep water, hit flinches,
  sword and fist variations, overhand throws, opening crates, the staff cast.
